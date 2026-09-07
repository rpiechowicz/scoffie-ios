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
    var height: CGFloat = 3.5
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

/// Jedna kolumna pigułki: podpis „B 100/150" i pod nim tor na PEŁNĄ szerokość
/// kolumny.
///
/// Trzeci układ tego komponentu i pierwszy, w którym pasek jest paskiem.
/// Pierwszy stawiał podpis nad torem, ale kolumny szły trzy w wierszu pod
/// wierszem kalorii — trzy poziomy tekstu, pigułka jak klocek. Drugi położył
/// podpis i tor w jednej linii, co zbiło wysokość, ale zabrało torowi całą
/// szerokość poza podpisem: przy trzech kolumnach zostawało na niego ~32 pt,
/// czyli kreska, a nie miernik. Do tego podpisy różnej długości („B 100/150"
/// kontra „T 40/70") dawały tory różnej długości i o różnych początkach, więc
/// nie dało się ich porównać ani wzrokiem prześlizgnąć po jednej linii.
///
/// Tutaj kolumna ma dwie linijki, ale W PIGUŁCE JEST JEDEN WIERSZ takich
/// kolumn — cztery równe, kalorie i trzy makra obok siebie. Wysokość wychodzi
/// niższa niż przy dwóch wierszach jednolinijkowych, a tor dostaje całą
/// szerokość kolumny: wszystkie cztery tej samej długości, wszystkie zaczynają
/// się w tym samym miejscu, więc widać je jako jedną siatkę.
///
/// Wartość i cel mają różną wagę i różny kolor. „100" jest tym, po co się
/// patrzy, „/150" jest odniesieniem — jednolity ciąg „100/150" kazał czytać
/// obie liczby, żeby wyłuskać pierwszą.
struct MacroMeter: View {
    /// Podpis na ekranie — jedna litera: K, B, T, W.
    let letter: String
    /// Pełna nazwa — wyłącznie dla VoiceOver, na ekranie nie ma na nią miejsca.
    let title: String
    let value: Int
    /// `nil`, gdy celu nie da się policzyć (brak sylwetki w profilu). Wtedy
    /// zostaje sama wartość, bez toru — pusty pasek obiecywałby cel, którego
    /// nie ma.
    let target: Int?
    let color: Color
    /// Jednostka w dopełniaczu, wyłącznie do zdania dla VoiceOver
    /// („…z 2100 kilokalorii").
    var unit: String = "gramów"
    /// Dopowiedzenie na koniec zdania dla VoiceOver — to, co widać z układu,
    /// ale czego nie da się usłyszeć z samych liczb.
    var accessibilityDetail: String?

    @Environment(\.colorScheme) private var scheme

    /// Wysokość toru. Osobna stała, bo kolumna bez celu musi zarezerwować
    /// dokładnie tyle samo miejsca — inaczej brak sylwetki w profilu
    /// rozjeżdżałby wysokości kolumn i pigułka robiła się schodkowa.
    private static let trackHeight: CGFloat = 4

    private var progress: Double? {
        guard let target, target > 0 else { return nil }
        return Double(value) / Double(target)
    }

    private var isOverTarget: Bool { (progress ?? 0) > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(letter)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(color)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: String(value))
                        .font(.system(size: 11.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isOverTarget ? color : Color.scLabel(scheme))
                        .contentTransition(.numericText())

                    if let target {
                        Text(verbatim: "/\(target)")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            if let progress {
                MacroProgressTrack(progress: progress, color: color, height: Self.trackHeight)
            } else {
                Color.clear.frame(height: Self.trackHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var text: String
        if let target {
            text = "\(title): \(value) z \(target) \(unit)"
            if isOverTarget { text += ", cel przekroczony" }
        } else {
            text = "\(title): \(value) \(unit)"
        }
        if let accessibilityDetail { text += ", \(accessibilityDetail)" }
        return text
    }
}
