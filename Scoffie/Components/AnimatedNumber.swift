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

    @State private var displayed: Double = 0
    @State private var didLoad = false

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
                // Tiny delay so the screen frame mounts before the count begins.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: loadDuration)) {
                        displayed = Double(target)
                    }
                }
            }
            .onChange(of: target) { _, newValue in
                withAnimation(.easeOut(duration: changeDuration)) {
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
