import SwiftUI

/// Znacznik wyboru „jedno z wielu” — JEDEN w całej aplikacji: obwódka,
/// a po zaznaczeniu obwódka w akcencie i kropka, która wyrasta ze środka.
///
/// Wcześniej było ich sześć: pierścień z kropką w diecie i celu (Ustawienia),
/// pełne koło z białą kropką w kreatorze, pełne koło z ptaszkiem 26 pt przy
/// wyborze przepisu do planu, 18 pt w planach Asystenta, jeszcze inne przy
/// motywie i przy zgłaszaniu odpowiedzi. Ptaszek w kółku mówi „zaznaczone
/// z wielu” — to robi `SCCheckbox`; tutaj wybór jest jeden.
struct SCRadioMark: View {
    let isOn: Bool
    var accent: Color = SCPalette.terracotta
    var size: CGFloat = 22

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? accent : Color.scFaint(scheme), lineWidth: 1.6)

            Circle()
                .fill(accent)
                .frame(width: size * 0.55, height: size * 0.55)
                .scaleEffect(isOn ? 1 : 0.3)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isOn)
        .accessibilityHidden(true)
    }
}

#Preview("SCRadioMark") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        HStack(spacing: 18) {
            SCRadioMark(isOn: false)
            SCRadioMark(isOn: true)
            SCRadioMark(isOn: true, accent: SCPalette.sage)
        }
    }
    .preferredColorScheme(.dark)
}
