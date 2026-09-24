import SwiftUI

/// Etykieta z ikoną w tincie akcentu — JEDNA w aplikacji: alergeny na karcie
/// „Dieta i alergeny” (`AllergenSummaryCard`) i punkty stron wprowadzenia
/// Asystenta. Ikona 10,5 i krótka nazwa 13/600 na kapsule 28 pt: tint
/// akcentu z obwódką w tym samym kolorze.
///
/// Wyniesiona z `AllergenTag` (24.09.2026), kiedy wprowadzenie Asystenta
/// zamieniło kartę trzech punktów na etykiety — zamiast drugiej kopii tego
/// samego stroju.
struct SCTag: View {
    let title: String
    let icon: String
    var accent: Color = SCPalette.terracotta

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            // VoiceOver czyta sam tytuł — nazwa glifu („leaf fill”) nic nie mówi.
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .bold))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(accent.opacity(scheme == .dark ? 0.16 : 0.10)))
        .overlay(Capsule(style: .continuous).strokeBorder(accent.opacity(0.35), lineWidth: 1))
        .fixedSize()
    }
}

#Preview("SCTag") {
    VStack(alignment: .leading, spacing: 10) {
        SCTag(title: "Gluten", icon: "leaf.fill")
        SCTag(title: "Pod Twoją dietę", icon: "leaf.fill", accent: SCPalette.sage)
        SCTag(title: "Dla całego domu", icon: "person.2.fill", accent: SCPalette.indigo)
    }
    .padding(20)
    .background(SCPageBackground(scheme: .dark).ignoresSafeArea())
    .preferredColorScheme(.dark)
}
