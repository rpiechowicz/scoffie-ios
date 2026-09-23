import SwiftUI

/// „✦ Ułóż” w nagłówku Planu — wejście do asystenta, który układa tydzień.
///
/// Pigułka w wariancie „soft” (`scSoftCapsule`), tej samej wysokości co
/// krążki obok (34 pt, cel dotyku 44). Podpis zamiast samej ikony: kółko
/// z iskierkami nic nie mówiło, póki ktoś w nie nie stuknął, i dlatego nad
/// pustym tygodniem musiała stać osobna karta, która je tłumaczyła.
struct PlanAssistantPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: MenuConstans.Assistant.icon)
                    .font(.system(size: 13, weight: .bold))

                Text("Ułóż")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
            }
            .foregroundStyle(SCPalette.terracotta)
            .padding(.leading, 11)
            .padding(.trailing, 13)
            .frame(height: 34)
            .scSoftCapsule()
            .scTapHeight(drawn: 34)
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel("Zaplanuj z asystentem")
        // Sterowanie głosem szuka słowa, które widać na ekranie.
        .accessibilityInputLabels(["Ułóż", "Zaplanuj z asystentem"])
    }
}

#Preview("PlanAssistantPill") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        PlanAssistantPill {}
    }
    .preferredColorScheme(.dark)
}
