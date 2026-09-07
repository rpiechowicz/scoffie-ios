import SwiftUI

/// Tor jednego makra: szare tło na to, czego brakuje, kolor na to, co już jest,
/// i osobna warstwa na nadmiar ponad cel.
///
/// Wspólny dla pigułki „Cel dnia" nad menu i dla legendy w arkuszu — obie
/// pokazują tę samą rzecz i muszą pokazywać ją tak samo. To NIE jest
/// `MacroSegmentBar`: tamten dzieli JEDEN pasek między trzy makra i mówi,
/// z czego składa się energia dnia; ten pokazuje JEDNO makro wobec JEGO
/// własnego celu. Pierwsze odpowiada na „co jem", drugie na „ile mi zostało" —
/// i to drugie pytanie zadaje się częściej.
///
/// **Przekroczony cel gasi bazę, a nie dokłada do niej.** Nadmiar rysowany po
/// prostu na pełnym pasku w tym samym kolorze był praktycznie niewidoczny —
/// sam cień na styku to za mało, żeby zauważyć go kątem oka. Tutaj pełne
/// wypełnienie schodzi do jednej trzeciej mocy, a pełną moc ma dopiero
/// nadwyżka: pasek zmienia się CAŁY, więc przejście przez cel widać, zanim
/// się przeczyta liczbę.
struct MacroProgressTrack: View {
    /// Udział celu. Powyżej 1 znaczy „ponad cel" i rysuje drugą warstwę.
    let progress: Double
    let color: Color
    var height: CGFloat = 4
    /// `nil` gasi animację — do miejsc, które sterują ruchem z zewnątrz.
    var animation: Animation? = .spring(response: 0.4, dampingFraction: 0.9)

    @Environment(\.colorScheme) private var scheme

    private var isOverTarget: Bool { progress > 1 }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filled = CGFloat(min(max(progress, 0), 1))
            // Sufit na drugiej warstwie: przy 300 % nadmiar i tak domknąłby
            // pasek, a trzecia warstwa niczego już nie dodaje.
            let over = CGFloat(min(max(progress - 1, 0), 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.scBarTrack(scheme))

                Capsule()
                    .fill(color)
                    .opacity(isOverTarget ? 0.3 : 1)
                    .frame(width: width * filled, height: height)

                // Rysowany ZAWSZE, nie pod `if` — przy `if` przejście przez
                // 100 % wstawiałoby warstwę skokiem. Przycięta do zera kapsuła
                // nie rysuje niczego, więc kosztu nie ma.
                Capsule()
                    .fill(color)
                    .frame(width: width * over, height: height)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .frame(height: height)
        }
        .frame(height: height)
        .animation(animation, value: progress)
        .accessibilityHidden(true)
    }
}

/// Podpis „B 100/150" nad własnym torem makra — jedna kolumna pigułki.
///
/// Litera niesie kolor, liczba niesie stan. Po przekroczeniu celu liczba
/// przechodzi w kolor swojego makra, żeby sygnał był i w pasku, i w tekście:
/// pasek widać kątem oka, liczbę widać, gdy się na nią patrzy, i żaden z tych
/// dwóch sposobów patrzenia nie powinien przegapić przekroczenia.
struct MacroMeter: View {
    let letter: String
    /// Pełna nazwa — wyłącznie dla VoiceOver, na ekranie nie ma na nią miejsca.
    let title: String
    let value: Int
    /// `nil`, gdy celu nie da się policzyć (brak sylwetki w profilu). Wtedy
    /// zostaje sama wartość, bez toru — pusty pasek obiecywałby cel, którego
    /// nie ma.
    let target: Int?
    let color: Color

    @Environment(\.colorScheme) private var scheme

    private var progress: Double? {
        guard let target, target > 0 else { return nil }
        return Double(value) / Double(target)
    }

    private var isOverTarget: Bool { (progress ?? 0) > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                Text(letter)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)

                Text(valueText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOverTarget ? color : Color.scLabel(scheme))
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if let progress {
                MacroProgressTrack(progress: progress, color: color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var valueText: String {
        guard let target else { return "\(value) g" }
        return "\(value)/\(target)"
    }

    private var accessibilityLabel: String {
        guard let target else { return "\(title): \(value) gramów" }
        let base = "\(title): \(value) z \(target) gramów"
        return isOverTarget ? base + ", cel przekroczony" : base
    }
}
