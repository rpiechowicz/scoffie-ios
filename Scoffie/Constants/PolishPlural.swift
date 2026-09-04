import SwiftUI

/// Polska liczba mnoga w jednym miejscu. Reguła jest nieoczywista i była już
/// przepisana z pamięci w kilku widokach — a każda kopia to szansa na
/// zgubienie wyjątku dla nastek („12 posiłków”, nie „12 posiłki”).
enum PolishPlural {
    /// Zwraca samo słowo w odpowiedniej formie, bez liczby — wywołania, które
    /// potrzebują liczby, składają ją same albo sięgają po `servings`/`meals`.
    ///
    /// - Parameters:
    ///   - one: forma dla 1, np. „porcja”.
    ///   - few: forma dla końcówek 2–4, np. „porcje”.
    ///   - many: forma dla reszty, w tym dla zera i dla nastek, np. „porcji”.
    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        // Znak nie wpływa na odmianę, a wartości ujemne potrafią przyjść
        // z odejmowania w liczniku — bierzemy moduł, żeby „-2” nie wpadło
        // w gałąź `many` przez ujemną resztę.
        let magnitude = abs(count)

        if magnitude == 1 { return one }

        // Nastki (12–14) łamią regułę ostatniej cyfry i muszą być sprawdzone
        // przed nią, inaczej „13” dostałoby formę od trójki.
        if (12...14).contains(magnitude % 100) { return many }

        return (2...4).contains(magnitude % 10) ? few : many
    }

    /// Liczba porcji z odmienionym rzeczownikiem, np. „2 porcje”.
    static func servings(_ count: Int) -> String {
        "\(count) \(form(count, one: "porcja", few: "porcje", many: "porcji"))"
    }

    /// Liczba porcji w bierniku, np. „na 2 porcje”.
    ///
    /// Osobna forma, bo mianownik z `servings` po przyimku „na” daje
    /// „Na 1 porcja” — dokładnie to, co pokazywał eyebrow sekcji składników.
    /// Różnica jest widoczna tylko dla jedynki („porcję” zamiast „porcja”),
    /// ale to najczęstszy stan tego ekranu: szczegół z katalogu otwiera się
    /// właśnie na jednej porcji.
    static func servingsAccusative(_ count: Int) -> String {
        "\(count) \(form(count, one: "porcję", few: "porcje", many: "porcji"))"
    }

    /// Liczba posiłków z odmienionym rzeczownikiem, np. „3 posiłki”.
    static func meals(_ count: Int) -> String {
        "\(count) \(form(count, one: "posiłek", few: "posiłki", many: "posiłków"))"
    }
}

/// Podgląd jest tu zamiast testu jednostkowego: pokazuje wszystkie klasy
/// odmiany naraz, więc błąd w regule widać gołym okiem bez uruchamiania apki.
private struct PolishPluralPreviewHost: View {
    /// Progi, na których reguła się łamie: jedynka, końcówki 2–4, nastki
    /// i powrót do „few” powyżej setki.
    private static let samples = [0, 1, 2, 4, 5, 11, 12, 14, 15, 21, 22, 25, 112]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.scCanvas(scheme).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.samples, id: \.self) { count in
                        HStack(spacing: 12) {
                            Text(PolishPlural.servings(count))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Biernik obok mianownika, bo cała różnica siedzi
                            // w jedynce — zestawione w jednym wierszu widać, że
                            // „1 porcja” i „na 1 porcję” to dwie różne formy.
                            Text("na \(PolishPlural.servingsAccusative(count))")
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(PolishPlural.meals(count))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                    }
                }
                .padding(24)
            }
        }
    }
}

#Preview("PolishPlural — dark") {
    PolishPluralPreviewHost()
        .preferredColorScheme(.dark)
}

#Preview("PolishPlural — light") {
    PolishPluralPreviewHost()
        .preferredColorScheme(.light)
}
