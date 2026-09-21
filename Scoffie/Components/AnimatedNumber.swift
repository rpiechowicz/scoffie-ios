import SwiftUI

// Plain count-up: render the rounded current value as static `Text`. SwiftUI
// interpolates the underlying Double via `Animatable.animatableData`, so the
// view re-renders many times during the animation — digits tick up in place,
// no sliding/rolling content transition.
private struct AnimatableInt: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        // `Text("\(n)")` resolves to LocalizedStringKey, which formats integers
        // per locale — Polish adds a thin space as a thousands separator and
        // SwiftUI happily breaks lines on it. Use verbatim to render "1110".
        Text(verbatim: String(Int(value.rounded())))
            .monospacedDigit()
    }
}

// Counts from 0 → target on first appear. On subsequent target changes it
// smoothly recounts from the current displayed value to the new target.
struct CountingNumber: View {
    let target: Int
    var loadDuration: Double = 0.9
    var changeDuration: Double = 0.45
    /// Własne krzywe zamiast `easeOut` z czasami wyżej — gdy licznik ma iść
    /// w parze z innym ruchem (pierścień, tor) i nie może z nim rozjechać.
    var loadAnimation: Animation? = nil
    var changeAnimation: Animation? = nil

    @State private var displayed: Double = 0
    @State private var didLoad = false
    @State private var latestTarget: Int?

    var body: some View {
        // Niewidoczny tekst DOCELOWEJ wartości rezerwuje szerokość od pierwszej
        // klatki, a licznik rysuje się na nim. Bez tego rosnąca liczba cyfr
        // („0" → „27") zmieniała szerokość widoku co klatkę animacji i całe
        // wiersze z licznikami — hero listy zakupów, nagłówki sekcji — jeździły
        // na boki przez cały czas trwania odliczania.
        Text(verbatim: String(target))
            .monospacedDigit()
            .hidden()
            .overlay(alignment: .trailing) {
                AnimatableInt(value: displayed)
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                latestTarget = target
                // Tiny delay so the screen frame mounts before the count begins.
                // Liczy do NAJŚWIEŻSZEGO celu, nie do przechwyconego: gdy cel
                // zmieni się w tych 50 ms, stary `target` z domknięcia cofałby
                // licznik po tym, jak `onChange` już pojechał do nowego.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(loadAnimation ?? .easeOut(duration: loadDuration)) {
                        displayed = Double(latestTarget ?? target)
                    }
                }
            }
            .onChange(of: target) { _, newValue in
                latestTarget = newValue
                withAnimation(changeAnimation ?? .easeOut(duration: changeDuration)) {
                    displayed = Double(newValue)
                }
            }
    }
}

// MARK: - Rolowanie cyfr

/// Liczba, której cyfry ROLUJĄ się w miejscu przy każdej zmianie — ta sama
/// animacja co w szczegółach posiłku (`CalendarPlate`: „60 min · 1208 kcal”
/// w „12 min · 510 kcal”). Do wartości, które TYKAJĄ (sekundy tury, licznik
/// puli, odliczanie), w przeciwieństwie do `CountingNumber`, które liczy od
/// zera przy wejściu. Jedno miejsce, żeby każdy zegar w aplikacji ruszał
/// się tak samo; `unit` doklejane po spacji („24 s”).
struct SCRollingNumber: View {
    let value: Int
    var unit: String? = nil
    var duration: Double = 0.3

    private var text: String {
        unit.map { "\(value) \($0)" } ?? String(value)
    }

    var body: some View {
        Text(verbatim: text)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .animation(.easeOut(duration: duration), value: value)
    }
}

// MARK: - Napis z liczącymi się liczbami

/// Gotowy napis, w którym KAŻDA liczba liczy się `CountingNumber`, a reszta
/// stoi — „12 dań · 49 produktów”, „8 z 11”, „1750 g”. Jeden klocek na
/// wszystkie liczniki w zdaniach, żeby nie składać ich za każdym razem
/// z trzech kawałków i żeby liczyły się tą samą animacją co duże liczniki.
///
/// Tylko do napisów JEDNOLINIJKOWYCH: kawałki stoją w `HStack`, więc całość
/// nie łamie się jak zwykły tekst. Daty („21 wrz”) zostawiać w `Text` —
/// liczący się dzień miesiąca nic nie mówi.
struct SCCountingText: View {
    let text: String
    var loadAnimation: Animation? = nil
    var changeAnimation: Animation? = nil

    init(_ text: String, loadAnimation: Animation? = nil, changeAnimation: Animation? = nil) {
        self.text = text
        self.loadAnimation = loadAnimation
        self.changeAnimation = changeAnimation
    }

    private enum Token {
        case text(String)
        case number(Int)
    }

    /// Ciągi cyfr → liczby, reszta → tekst. Cyfry dłuższe niż 9 znaków
    /// zostają tekstem (to już nie jest licznik, tylko np. numer).
    private var tokens: [Token] {
        var result: [Token] = []
        var buffer = ""
        var bufferIsDigits = false

        func flush() {
            guard !buffer.isEmpty else { return }
            if bufferIsDigits, buffer.count <= 9, let value = Int(buffer) {
                result.append(.number(value))
            } else {
                result.append(.text(buffer))
            }
            buffer = ""
        }

        for character in text {
            let isDigit = character.isASCII && character.isNumber
            if isDigit != bufferIsDigits { flush() }
            bufferIsDigits = isDigit
            buffer.append(character)
        }
        flush()
        return result
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case .text(let part):
                    Text(verbatim: part)
                case .number(let value):
                    CountingNumber(
                        target: value,
                        loadAnimation: loadAnimation,
                        changeAnimation: changeAnimation
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}
