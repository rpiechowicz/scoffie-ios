import SwiftUI

/// Pole wyboru aplikacji: zaokrąglony kwadrat 24 pt (promień 8). Gdy
/// zaznaczone — gradient akcentu wyskakuje ze środka, ptaszek za nim,
/// a pod spodem pojawia się poświata w kolorze akcentu. Gdy nie — sama
/// obwódka.
///
/// Jedno na całą aplikację: „mam w domu” w szczegółach posiłku (indygo)
/// i „kupione” na liście zakupów (szałwia) mają wyglądać i ruszać się tak
/// samo. Poświata wychodzi poza ramkę, więc kontener nie może przycinać
/// wiersza na boki (patrz roleta w `ShoppingAisleSection`).
struct SCCheckbox: View {
    let on: Bool
    var accent: Color = SCPalette.indigo
    var size: CGFloat = 24

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size / 3, style: .continuous)
        let stroke = scheme == .dark
            ? SCPalette.labelDark.opacity(0.22)
            : SCPalette.labelLight.opacity(0.24)

        ZStack {
            shape
                .strokeBorder(stroke, lineWidth: 1.5)
                .opacity(on ? 0 : 1)

            shape
                .fill(
                    LinearGradient(
                        colors: [accent.mix(white: 0.08), accent.mix(black: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(on ? 1 : 0.55)
                .opacity(on ? 1 : 0)

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .heavy))
                .foregroundStyle(SCPalette.labelDark)
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                .scaleEffect(on ? 1 : 0.4)
                .opacity(on ? 1 : 0)
        }
        .frame(width: size, height: size)
        .shadow(color: on ? accent.opacity(0.4) : .clear, radius: 5, x: 0, y: 3)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: on)
    }
}
