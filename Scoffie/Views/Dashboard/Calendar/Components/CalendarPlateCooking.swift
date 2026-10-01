import SwiftUI

// Kalendarz × tryb Gotuj — wejście z talerza (D23, makieta EC41) i talerz
// wstrzymanego gotowania (PS1). Opis: scoffie-design `docs/GOTUJ.md`
// („Wejścia”), decyzje: `docs/workstreams/gotuj/README.md` §13.5–13.6.

/// Co tryb Gotuj ma do powiedzenia o daniu na talerzu.
///
/// Liczy ekran (`CalendarView.plateItems`), talerz tylko rysuje — jak
/// resztę stanu dania.
enum CalendarPlateCooking: Equatable {
    /// Scenariusz leży w telefonie — „play” startuje gotowanie z porcjami
    /// z planu (D11). W każdy dzień i o każdej porze; pora gotowania mówi
    /// tylko, czy przycisk jest pełny, czy „soft”.
    case ready
    /// Wstrzymane gotowanie TEGO wpisu planu: obręcz = pierścień kroków,
    /// „Krok 8 z 12” i trwające timery pod talerzem. `step` od zera.
    case paused(step: Int, steps: Int)
}

/// Pigułki trwających timerów pod talerzem wstrzymanego gotowania (PS1):
/// mini-pierścień, nazwa i czas w kolorze timera, tykające co sekundę.
/// Bez trwających timerów — zwykły rząd pigułek (`fallback`), żeby rząd
/// nigdy nie był pusty i podpis trzymał wysokość.
///
/// WSZYSTKIE timery w jednym rzędzie (runda 5: „ograniczenie do 2 — ubierz
/// to w UX, jak są np. 4 włączone”), w najbogatszej postaci, która się
/// mieści (`ViewThatFits`): z nazwami, potem same pierścienie z czasem
/// (każdy timer ma swój kolor), a gdy i to za mało — trzy pierwsze i „+N”.
/// Rząd zostaje jeden: drugi rząd podnosiłby wszystko pod talerzem.
struct CalendarCookTimerPills<Fallback: View>: View {
    let session: CookSession
    @ViewBuilder let fallback: () -> Fallback

    /// Zegar stoi, gdy Kalendarz nie jest wybraną zakładką (zakładki żyją
    /// pod spodem — `NavigationMenu`).
    @Environment(\.scTabIsActive) private var isActiveTab

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isActiveTab)) { context in
            let timers = running(at: context.date)
            if timers.isEmpty {
                fallback()
            } else {
                ViewThatFits(in: .horizontal) {
                    pills(timers, compact: false)
                    pills(timers, compact: true)
                    pills(Array(timers.prefix(3)), compact: true, more: timers.count - 3)
                }
            }
        }
    }

    private func pills(_ timers: [CookDockTimer], compact: Bool, more: Int = 0) -> some View {
        HStack(spacing: 6) {
            ForEach(timers) { item in
                CalendarCookTimerPill(item: item, compact: compact)
                    .transition(.opacity)
            }
            if more > 0 {
                CalendarPlateChip(text: "+\(more)")
                    .accessibilityLabel("Jeszcze \(more) \(PolishPlural.form(more, one: "timer", few: "timery", many: "timerów"))")
            }
        }
    }

    /// Trwające i po czasie — te same, które arkusz „Wychodzisz z gotowania?”
    /// pokazał przy wstrzymaniu.
    private func running(at now: Date) -> [CookDockTimer] {
        session.timerLineup(now: now).filter { item in
            switch item.status {
            case .running, .overdue: true
            default: false
            }
        }
    }
}

/// Jedna pigułka timera — skorupa `CalendarPlateChip` (30 pt, `chipBg`,
/// `tileStroke`, 12,5 / 700), w środku pierścień 13 pt z łukiem POZOSTAŁEGO
/// czasu (jak w doku), nazwa w piśmie i czas w kolorze timera. Zwarta —
/// bez nazwy: kolor pierścienia i czasu mówi, który to timer.
private struct CalendarCookTimerPill: View {
    let item: CookDockTimer
    var compact = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = item.accent.color
        let time = CookDockLabels.time(item.status)
        HStack(spacing: 6) {
            CookTimerRing(fraction: item.status.remainingFraction, color: color, lineWidth: 2)
                .frame(width: 13, height: 13)
            if !compact {
                Text(item.timer.label)
                    .foregroundStyle(Color.scLabel(scheme))
            }
            Text(time)
                .monospacedDigit()
                .foregroundStyle(color)
                .cookTicking(time, countsDown: !item.status.isOverdue)
        }
        .font(.system(size: 12.5, weight: .bold))
        .tracking(-0.15)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, compact ? 10 : 12)
        .frame(height: 30)
        .background(Capsule().fill(Color.scChipBg(scheme)))
        .overlay(Capsule().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CookDockLabels.accessibility(item))
    }
}
