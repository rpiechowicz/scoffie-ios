import SwiftUI

/// „✦ Ułóż” w nagłówku Planu — wejście do asystenta, który układa tydzień.
///
/// Pigułka w wariancie „soft” (`scSoftCapsule`), tej samej wysokości co
/// krążki obok (34 pt, cel dotyku 44). Podpis zamiast samej ikony: kółko
/// z iskierkami nic nie mówiło, póki ktoś w nie nie stuknął.
///
/// Pusty tydzień (`invites`) = pigułka ODDYCHA (27.09.2026, Rafał: zamiast
/// karty „Ten tydzień jest jeszcze pusty” nad osią dnia): terakotowa poświata
/// pod kapsułą wzbiera i opada, a sama pigułka lekko rośnie. Siła dobrana
/// w dwóch krokach tego samego dnia: pierwsza wersja na wdechu zalewała
/// pigułkę („zrób bardziej delikatny”), druga ledwo było widać („ciut
/// mocniejszy, ale niewiele”) — stąd liczby pośrodku. Oddech to czysta
/// funkcja czasu w `TimelineView`, jak w `SCLivingMark` — `repeatForever`
/// na `@State` zastygał, gdy rodzic przebudował widok. Zegar staje na
/// niewybranej zakładce (`scTabIsActive`); przy „Ogranicz ruch” poświata
/// stoi w połowie oddechu, bez ruchu.
struct PlanAssistantPill: View {
    var invites: Bool = false
    let action: () -> Void

    @Environment(\.scTabIsActive) private var isActiveTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tempo oddechu znaku, który czeka na użytkownika (`SCLivingMark`,
    /// nastrój `attentive`) — spokojne, ale żywsze od spoczynku (4,2 s).
    private static let period: Double = 2.6

    private var breathes: Bool { invites && isActiveTab && !reduceMotion }

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !breathes)) { context in
                pill(breath: breath(at: context.date))
            }
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .animation(.smooth(duration: 0.5), value: invites)
        .accessibilityLabel("Zaplanuj z asystentem")
        // Sterowanie głosem szuka słowa, które widać na ekranie.
        .accessibilityInputLabels(["Ułóż", "Zaplanuj z asystentem"])
        .accessibilityHint(invites ? "Ten tydzień jest jeszcze pusty" : "")
    }

    /// 0…1. Bez zaproszenia — zero (pigułka jak każda inna akcja nagłówka);
    /// przy „Ogranicz ruch” — stała połowa, żeby pusty tydzień dalej było
    /// widać, tylko bez ruchu.
    private func breath(at date: Date) -> Double {
        guard invites else { return 0 }
        guard breathes else { return 0.5 }
        let t = date.timeIntervalSinceReferenceDate
        return (1 - cos(2 * .pi * t / Self.period)) / 2
    }

    private func pill(breath b: Double) -> some View {
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
        // Poświata POD kapsułą: tint „soft” jest półprzezroczysty, więc przy
        // wdechu cieplej robi się też wnętrze pigułki. Ujemny padding
        // rozszerza kapsułę równo ze wszystkich stron (skala rozciągałaby ją
        // bardziej w poziomie niż w pionie) i nie rusza układu nagłówka.
        .background {
            Capsule(style: .continuous)
                .fill(SCPalette.terracotta.opacity(invites ? 0.05 + 0.16 * b : 0))
                .padding(-(1 + 4 * b))
                .blur(radius: 4.5)
        }
        .scaleEffect(1 + 0.028 * b)
        .scTapHeight(drawn: 34)
    }
}

#Preview("PlanAssistantPill") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        VStack(spacing: 24) {
            PlanAssistantPill {}
            PlanAssistantPill(invites: true) {}
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("PlanAssistantPill · Light") {
    ZStack {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        VStack(spacing: 24) {
            PlanAssistantPill {}
            PlanAssistantPill(invites: true) {}
        }
    }
    .preferredColorScheme(.light)
}
