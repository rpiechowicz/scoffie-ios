import SwiftUI

// Minus / plus zamiast pola tekstowego. Wartości, które ten stepper reguluje —
// gramy makra, liczba porcji — zmienia się o krok w jedną albo drugą stronę,
// a nie wpisuje od zera, więc nie ma tu żadnego stanu pośredniego do zepsucia.
//
// Wygląd jest przeniesiony jeden do jednego ze steppera makr w ustawieniach:
// dwa przyciski 34x30 rozdzielone hairline'em, całość na pigułce z obwódką.
struct WMStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...12
    var step: Int = 1
    /// Etykieta czytana przez VoiceOver, np. „Liczba porcji”.
    var accessibilityTitle: String
    /// Tekst wartości dla VoiceOver, np. „2 porcje”.
    var accessibilityValue: String
    var onChange: ((Int) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus", enabled: canDecrement) {
                adjust(by: -step)
            }

            Rectangle()
                .fill(Color.wmTileStroke(scheme))
                .frame(width: 1, height: 18)

            stepButton(systemName: "plus", enabled: canIncrement) {
                adjust(by: step)
            }
        }
        .background(Capsule().fill(Color.wmChipBg(scheme)))
        .overlay(Capsule().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityValue)
    }

    private var canDecrement: Bool { value > range.lowerBound }
    private var canIncrement: Bool { value < range.upperBound }

    /// Klamrujemy zamiast blokować samo `value`, bo wiązanie może przyjść
    /// z zewnątrz już poza zakresem (np. wartość z serwera po zmianie limitu)
    /// i pierwsze tapnięcie ma wtedy wciągnąć ją z powrotem do widełek.
    private func adjust(by delta: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + delta))
        guard next != value else { return }

        withAnimation(.smooth(duration: 0.18)) { value = next }
        onChange?(next)
    }

    private func stepButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WMPalette.terracotta)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// Preview trzyma wartość u siebie, bo `WMStepper` bierze `Binding` i bez
/// właściciela stanu w podglądzie nic by się nie ruszało.
private struct WMStepperPreviewHost: View {
    @State private var servings = 2
    @State private var atUpperBound = 12
    @State private var protein = 140

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.wmCanvas(scheme).ignoresSafeArea()

            VStack(spacing: 24) {
                row(title: "Liczba porcji") {
                    WMStepper(
                        value: $servings,
                        accessibilityTitle: "Liczba porcji",
                        accessibilityValue: PolishPlural.servings(servings)
                    )
                }

                row(title: "Na krańcu zakresu") {
                    WMStepper(
                        value: $atUpperBound,
                        accessibilityTitle: "Liczba porcji",
                        accessibilityValue: PolishPlural.servings(atUpperBound)
                    )
                }

                row(title: "Krok co 5 g") {
                    WMStepper(
                        value: $protein,
                        range: 0...300,
                        step: 5,
                        accessibilityTitle: "Białko",
                        accessibilityValue: "\(protein) gramów"
                    )
                }
            }
            .padding(24)
        }
    }

    private func row<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.wmLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            content()
        }
    }
}

#Preview("WMStepper — dark") {
    WMStepperPreviewHost()
        .preferredColorScheme(.dark)
}

#Preview("WMStepper — light") {
    WMStepperPreviewHost()
        .preferredColorScheme(.light)
}
