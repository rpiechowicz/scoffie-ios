import SwiftUI

// Wiersz produktu na Zakupach v2 — kółko · nazwa (z daniami pod spodem) ·
// znacznik „Dziś” · ilość.
//
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-kit.jsx` → `ShopRow`, `components/shop-v2-final.jsx`).
//
// Wiersz nie jest kartą. Hairline biegnie WYŁĄCZNIE pod treścią, czyli od
// nazwy w prawo — kolumna kółek zostaje czysta i widać ją jako jedną pionową
// ścieżkę do odhaczania, a nie jako lewą krawędź szesnastu osobnych kafli.
// Ten sam zabieg co na osi dnia w Planie i w Kalendarzu.

/// Kółko odhaczenia — szałwia z ptaszkiem, gdy kupione; sama obwódka, gdy nie.
///
/// Szałwia, a nie kolor działu: „kupione” to jeden stan na całej liście
/// i musi wyglądać tak samo w warzywach, co w nabiale. Kolor działu niesie
/// nagłówek sekcji i pasek postępu.
struct ShoppingCheckCircle: View {
    let on: Bool
    var size: CGFloat = 22
    var accent: Color = SCPalette.sage

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.scFaint(scheme), lineWidth: 1.5)
                .opacity(on ? 0 : 1)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent, accent.mix(black: 0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Skala zamiast samego krycia: kółko „zapada się” w środek,
                // gdy odznaczasz produkt, i wyskakuje, gdy odhaczasz — ruch
                // jest w tym samym miejscu, w którym stoi palec.
                .scaleEffect(on ? 1 : 0.6)
                .opacity(on ? 1 : 0)

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.44, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
                .scaleEffect(on ? 1 : 0.4)
                .opacity(on ? 1 : 0)
        }
        .frame(width: size, height: size)
        .shadow(color: on ? accent.opacity(0.35) : .clear, radius: 4, x: 0, y: 3)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: on)
    }
}

/// Znacznik „Dziś” przy produkcie potrzebnym do dzisiejszego dania.
struct ShoppingTodayTag: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text("DZIŚ")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(SCPalette.terracotta)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.12))
            )
    }
}

struct ShoppingProductRow: View {
    let name: String
    let amount: String
    /// Dania, z których wziął się produkt — „Omlet ze szpinakiem · Krem
    /// z pomidorów”. `nil` chowa całą drugą linijkę, nie zostawia pustej.
    var dishes: String?
    let bought: Bool
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
                ShoppingCheckCircle(on: bought)

                content
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                ShoppingTodayTag()
                    .transition(.scale.combined(with: .opacity))
            }

            Text(amount)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.1)
                .monospacedDigit()
                .foregroundStyle(bought ? Color.scFaint(scheme) : Color.scMuted(scheme))
                .lineLimit(1)
                // Ilość nigdy się nie zwija ani nie skaluje — to jedyna liczba
                // w wierszu i musi dać się przeczytać z ręki w sklepie.
                // Miejsce oddaje jej nazwa produktu, nie odwrotnie.
                .fixedSize()
        }
        .frame(minHeight: dishes == nil ? 46 : 52)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
            }
        }
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
                showsTodayTag: true
            )
            ShoppingProductRow(
                name: "Pomidory krojone z puszki bez skórki",
                amount: "750 g",
                dishes: "Krem z pomidorów · Ryż z warzywami",
                bought: false
            )
            ShoppingProductRow(
                name: "Masło",
                amount: "250 g",
                dishes: "Omlet ze szpinakiem",
                bought: true,
                isLast: true
            )
        }
        .padding(20)
    }
    .preferredColorScheme(.dark)
}
