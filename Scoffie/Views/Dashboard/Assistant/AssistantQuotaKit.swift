import StoreKit
import SwiftUI

// Widoki „pula wykorzystana”: ile poszło (kreseczki zamiast samego zdania),
// kiedy wraca (plan miesięczny) albo co daje plan (próba) — i że plan oraz
// zakupy działają dalej bez asystenta. Liczby WYŁĄCZNIE z serwera
// (`AgentUsageDTO`); plan z katalogu tylko PODPOWIADA („Polecamy”), nigdy nie
// mówi „Twój” — patrz CLAUDE.md, „Plany asystenta”.

// MARK: - Fakty

/// Wszystko, co widoki puli pokazują — policzone raz, przez ekran.
struct AssistantQuotaFacts: Equatable {
    let messages: AgentQuotaDTO
    let plans: AgentQuotaDTO
    let isTrial: Bool
    /// Kiedy pula wraca; `nil` na próbie (nie odnawia się) albo gdy serwer
    /// nie podał daty.
    let resetsAt: Date?
    /// Plan polecany dla wielkości domu — tylko na próbie i tylko, gdy znamy
    /// liczbę domowników.
    let suggestion: Suggestion?

    struct Suggestion: Equatable {
        let name: String
        /// Wiadomości w miesiącu — obietnica z katalogu (`SubscriptionPlan`).
        let messages: Int
        /// Cena z App Store, a bez sieci — z cennika.
        let price: String
    }

    static func make(usage: AgentUsageDTO?, householdSize: Int, subscriptions: SubscriptionStore?) -> AssistantQuotaFacts? {
        guard let usage else { return nil }
        var suggestion: Suggestion?
        if usage.isTrial, let plan = PlansSheet.plan(forHousehold: householdSize) {
            let price = subscriptions?.product(for: plan)?.displayPrice ?? plan.fallbackPrice
            suggestion = Suggestion(name: plan.name, messages: plan.messages, price: price)
        }
        return AssistantQuotaFacts(
            messages: usage.messages,
            plans: usage.plans,
            isTrial: usage.isTrial,
            resetsAt: usage.isTrial ? nil : AgentStore.parseTimestamp(usage.resetsAt),
            suggestion: suggestion
        )
    }

    /// „1 października”.
    var resetDay: String? {
        resetsAt.map { Self.dayFormatter.string(from: $0) }
    }

    /// „dziś”, „jutro”, „za 8 dni” — po dniach kalendarza, nie po 24 h.
    func resetDistance(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let resetsAt else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: resetsAt)
        ).day ?? 0
        switch days {
        case ...0: return "dziś"
        case 1: return "jutro"
        default: return "za \(days) dni"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()
}

// MARK: - Miernik

/// Jedna pula: nazwa, „5 z 5” i kreseczki — po jednej na wiadomość, dopóki
/// pula jest mała (próba), a przy dużej jeden pasek. Z `revealed` kreseczki
/// zapełniają się po kolei, a liczba roluje od zera.
struct AssistantQuotaMeter: View {
    let title: String
    let quota: AgentQuotaDTO
    var revealed: Bool = true
    var delay: Double = 0

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Do tylu kreseczek pula rysuje się pojedynczo.
    private static let maxPips = 12

    private var shownUsed: Int { revealed ? quota.used : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AssistantLook.muted(scheme))
                Spacer(minLength: 8)
                Text("\(shownUsed) z \(quota.limit)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .contentTransition(.numericText(value: Double(shownUsed)))
                    .animation(countAnimation, value: revealed)
            }
            track
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): wykorzystano \(quota.used) z \(quota.limit)")
    }

    @ViewBuilder
    private var track: some View {
        if quota.limit > 0, quota.limit <= Self.maxPips {
            HStack(spacing: 4) {
                ForEach(0..<quota.limit, id: \.self) { index in
                    Capsule()
                        .fill(index < shownUsed ? AssistantLook.terraFill(scheme) : AssistantLook.ink(scheme).opacity(0.09))
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                        .animation(pipAnimation(index), value: revealed)
                }
            }
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(AssistantLook.ink(scheme).opacity(0.09))
                    Capsule()
                        .fill(AssistantLook.terraFill(scheme))
                        .frame(width: geometry.size.width * (revealed ? quota.fraction : 0))
                        .animation(countAnimation, value: revealed)
                }
            }
            .frame(height: 6)
        }
    }

    /// Jawne właściwości zamiast `reduceMotion ? nil : …` w argumencie (SE-0418).
    private var countAnimation: Animation? {
        if reduceMotion { return nil }
        return .smooth(duration: 0.7).delay(delay)
    }

    private func pipAnimation(_ index: Int) -> Animation? {
        if reduceMotion { return nil }
        return .smooth(duration: 0.3).delay(delay + 0.06 * Double(index))
    }
}

// MARK: - Panel w powitaniu

/// Kontekst powitania przy wykorzystanej puli: obie pule jako kreseczki,
/// a pod kreską — kiedy wraca (plan miesięczny) albo co daje polecany plan
/// (próba). Kafel jak każda karta w aplikacji.
struct AssistantQuotaPanel: View {
    let facts: AssistantQuotaFacts
    var revealed: Bool = true
    var delay: Double = 0

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                AssistantQuotaMeter(title: "Wiadomości", quota: facts.messages, revealed: revealed, delay: delay)
                if facts.plans.limit > 0 {
                    AssistantQuotaMeter(title: "Zapisy planu", quota: facts.plans, revealed: revealed, delay: delay + 0.12)
                }
            }
            .padding(14)

            if hasFooter {
                Rectangle()
                    .fill(AssistantLook.hair(scheme))
                    .frame(height: 1)
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.scTileBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .frame(maxWidth: 340)
    }

    private var hasFooter: Bool { facts.resetDay != nil || facts.suggestion != nil }

    @ViewBuilder
    private var footer: some View {
        if let day = facts.resetDay {
            AssistantQuotaResetRow(day: day, distance: facts.resetDistance())
        } else if let suggestion = facts.suggestion {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AssistantLook.terra(scheme))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Polecamy „\(suggestion.name)”")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(AssistantLook.ink(scheme))
                    Text("\(suggestion.messages) wiadomości co miesiąc · \(suggestion.price)")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.muted(scheme))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// „↻ Wraca 1 października · za 8 dni” — odległość roluje, gdy zmieni się dzień.
struct AssistantQuotaResetRow: View {
    let day: String
    let distance: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(AssistantLook.terra(scheme))
            Text("Wraca \(day)")
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(AssistantLook.ink(scheme))
            Spacer(minLength: 8)
            if let distance {
                Text(distance)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.35), value: distance)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Karta zamiast pola

/// Karta w miejscu pola wiadomości, gdy pula się skończyła — w rozmowie
/// (próba) i wszędzie (plan miesięczny). Śpiący znak, jedno zdanie o skutku,
/// kreseczki wiadomości i jedna akcja: próba prowadzi do planów, plan
/// miesięczny — do limitów (tam jest data i rozkład na domowników).
struct AssistantQuotaSpentCard: View {
    let facts: AssistantQuotaFacts?
    /// Próba (bez odnowienia) czy plan miesięczny. Osobno od `facts`, bo
    /// blokada bywa znana, zanim dojdą liczby.
    let isTrial: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var title: String {
        isTrial ? "Darmowe wiadomości wykorzystane" : "Pula na ten miesiąc wykorzystana"
    }

    private var subtitle: String {
        if isTrial {
            if let suggestion = facts?.suggestion {
                return "Rozmowy i plan zostają. „\(suggestion.name)” to \(suggestion.messages) wiadomości co miesiąc."
            }
            return "Rozmowy i plan zostają."
        }
        if let day = facts?.resetDay {
            return [("Wraca " + day), facts?.resetDistance()].compactMap { $0 }.joined(separator: " · ")
        }
        return "Wróci z odnowieniem planu."
    }

    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    // Znak drzemie — asystent odpoczywa, aplikacja nie.
                    SCLivingMark(mood: .sleeping, color: AssistantLook.terraFill(scheme), size: 20, glows: false)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 16.5, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(AssistantLook.ink(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(AssistantLook.muted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.35), value: subtitle)
                    }
                }

                if let facts {
                    AssistantQuotaMeter(title: "Wiadomości", quota: facts.messages)
                }

                if isTrial {
                    AssistantPrimaryButton(action: AssistantCardAction(title: "Zobacz plany", icon: "arrow.right", action: action))
                } else {
                    AssistantGhostButton(action: AssistantCardAction(title: "Limity asystenta", icon: "chart.bar", action: action))
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 16)
        }
        .accessibilityElement(children: .contain)
    }
}
