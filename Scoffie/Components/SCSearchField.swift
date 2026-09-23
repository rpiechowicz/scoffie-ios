import SwiftUI

/// Pole szukania — JEDNO w całej aplikacji: kapsuła 44 pt na `scTileBg`,
/// lupa, krzyżyk czyszczący, a w trakcie pisania obwódka w terakocie.
///
/// Wcześniej każdy ekran miał własne: pigułka na Przepisach, niższa pigułka
/// bez krzyżyka w liście kategorii, zaokrąglony prostokąt przy wyborze
/// przepisu do planu i jeszcze inny, na `scChipBg`, w wykluczaniu
/// składników — cztery pola w odległości jednego stuknięcia od siebie.
/// Własne zostaje tylko pływające pole rozmów Asystenta: stoi na dole
/// ekranu, w języku arkuszy asystenta (`AssistantLook`).
struct SCSearchField: View {
    let prompt: String
    @Binding var text: String
    /// Fokus z zewnątrz — gdy ekran sam chowa klawiaturę („Gotowe”).
    /// `nil` = pole trzyma fokus samo.
    var focus: FocusState<Bool>.Binding? = nil
    /// Obwódka przy fokusie prowadzonym z zewnątrz — podaje ją ekran, bo
    /// tylko on czyta swój `@FocusState` w `body`; odczyt cudzego fokusu
    /// w polu nie musi go przerysować.
    var isActive: Bool? = nil
    var onSubmit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @FocusState private var ownFocus: Bool

    private var focusBinding: FocusState<Bool>.Binding { focus ?? $ownFocus }
    private var isFocused: Bool { isActive ?? ownFocus }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme).opacity(0.7))
                .accessibilityHidden(true)

            TextField(text: $text) {
                Text(prompt)
                    .foregroundStyle(Color.scMuted(scheme).opacity(0.7))
            }
            .font(.system(size: 16))
            .tracking(-0.2)
            .foregroundStyle(Color.scLabel(scheme))
            .tint(SCPalette.terracotta)
            .focused(focusBinding)
            .submitLabel(.search)
            .onSubmit { onSubmit?() }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść szukanie")
                .transition(.opacity)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background(
            Capsule(style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    isFocused ? SCPalette.terracotta.opacity(0.55) : Color.scTileStroke(scheme),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .contentShape(Capsule(style: .continuous))
        // Stuknięcie w brzeg kapsuły (lupa, margines) też stawia kursor —
        // pole tekstowe jest węższe niż to, co wygląda na pole.
        .onTapGesture {
            let binding = focusBinding
            binding.wrappedValue = true
        }
        .animation(.smooth(duration: 0.18), value: isFocused)
        .animation(.smooth(duration: 0.18), value: text.isEmpty)
    }
}

#Preview("SCSearchField") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        VStack(spacing: 12) {
            SCSearchField(prompt: "Szukaj w śniadaniach", text: .constant(""))
            SCSearchField(prompt: "Szukaj w śniadaniach", text: .constant("owsianka"))
        }
        .padding(.horizontal, 20)
    }
    .preferredColorScheme(.dark)
}
