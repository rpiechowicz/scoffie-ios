import SwiftUI

/// Limity asystenta — dwa pierścienie z liczbą „zostało" (projekt „Asystent
/// Zgoda", 3.09.2026) w dwóch wariantach z tego samego projektu:
/// - **próba** (`tier == TRIAL`): jednorazowa pula bez odnowienia, bez
///   rozkładu na domowników, stopka „Odblokuj PRO";
/// - **PRO**: pula miesięczna, rozkład na domowników (pula jest wspólna,
///   ktoś zawsze pyta „kto to zużył"), „Zarządzaj subskrypcją" tylko gdy PRO
///   pochodzi z subskrypcji, nie z nadania.
/// Reguły „co się liczy" są jedyną rzeczą, która generuje zgłoszenia:
/// „Zmień" to wiadomość, oglądanie propozycji jest darmowe.
struct AssistantUsageSheet: View {
    let store: AgentStore
    /// „Odblokuj PRO" (tylko na próbie) — arkusz zamyka się, otwiera paywall.
    var onUpgrade: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(\.sessionStore) private var sessionStore
    @State private var usage: AgentUsageDTO?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WMPageBackground(scheme: scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        EditorialSheetHeader(eyebrow: "Asystent AI", title: "Limity asystenta") {
                            dismiss()
                        }

                        if let usage {
                            planLine(usage)

                            quotaCard(
                                label: "Wiadomości",
                                quota: usage.messages,
                                color: WMPalette.terracotta,
                                unit: usage.isTrial ? "darmowych" : "w tym miesiącu",
                                note: usage.isTrial
                                    ? "Każde pytanie do asystenta."
                                    : ((usage.byUser?.isEmpty == false)
                                        ? "Wspólna pula całego domu. Kto ile wykorzystał:"
                                        : "Wspólna pula całego domu."),
                                perUser: usage.isTrial ? [] : (usage.byUser?.map { ($0.userId, $0.displayName, $0.messages) } ?? [])
                            )
                            quotaCard(
                                label: "Zapisane plany",
                                quota: usage.plans,
                                color: WMPalette.sage,
                                unit: usage.isTrial ? "na próbę" : "w tym miesiącu",
                                note: usage.isTrial
                                    ? "Propozycje oglądasz bez limitu, zapis liczy się raz."
                                    : "Każde „Dodaj do planu”: tydzień, dzień albo podmiana.",
                                perUser: []
                            )
                            rulesCard(usage)
                        } else if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            Text("Nie udało się pobrać limitów. Spróbuj ponownie za chwilę.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.wmMuted(scheme))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, footerReserve)
                }
                .scrollIndicators(.hidden)

                if let usage, usage.isTrial || usage.showsManageSubscription {
                    footer(usage)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .task {
            usage = await store.loadUsage()
            isLoading = false
        }
    }

    private var footerReserve: CGFloat {
        guard let usage else { return 28 }
        return (usage.isTrial || usage.showsManageSubscription) ? 120 : 28
    }

    // MARK: - Nagłówek planu

    private func planLine(_ usage: AgentUsageDTO) -> some View {
        let tone: Color = usage.isTrial ? WMPalette.butter : WMPalette.sage
        let tint: Color = usage.isTrial ? Color.wmButterTint(scheme) : Color.wmSageTint(scheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text(usage.isTrial ? "Dostęp próbny" : (sessionStore.currentHouseholdName.map { "PRO · \($0)" } ?? "PRO"))
                .font(.system(size: 12, weight: .bold))
                .tracking(0.2)
                .foregroundStyle(tone)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(tint))
                .lineLimit(1)
            Text(usage.isTrial
                 ? "jednorazowo, bez odnowienia"
                 : "odnowienie \(usage.resetsAt.map(Self.resetLabel) ?? "co miesiąc") · wspólnie dla domu")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.wmMuted(scheme))
                .padding(.leading, 2)
        }
    }

    // MARK: - Karty kwot

    private func quotaCard(label: String, quota: AgentQuotaDTO, color: Color, unit: String, note: String, perUser: [(String, String, Int)]) -> some View {
        AssistantSurfaceCard(padding: 14) {
            HStack(spacing: 16) {
                ring(fraction: quota.fraction, color: color) {
                    VStack(spacing: 0) {
                        Text("\(quota.remaining)")
                            .font(.system(size: 26, weight: .bold))
                            .tracking(-0.8)
                            .monospacedDigit()
                            .foregroundStyle(Color.wmLabel(scheme))
                        Text("zostało")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.wmMuted(scheme))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    AssistantSectionLabel(text: label, color: color)
                    Text("\(quota.used) z \(quota.limit) \(unit)")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .monospacedDigit()
                        .foregroundStyle(quota.remaining == 0 ? color : Color.wmLabel(scheme))
                    Text(note)
                        .font(.system(size: 12.5))
                        .lineSpacing(1.5)
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): zostało \(quota.remaining) z \(quota.limit)")

            if !perUser.isEmpty {
                VStack(spacing: 6) {
                    ForEach(perUser, id: \.0) { row in
                        HStack(spacing: 8) {
                            memberAvatar(userId: row.0, name: row.1)
                            Text(HouseholdMemberStyle.shortName(row.1))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.wmLabel(scheme))
                                .frame(width: 64, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.wmBarTrack(scheme))
                                    Capsule().fill(color).frame(width: geometry.size.width * (quota.used > 0 ? Double(row.2) / Double(quota.used) : 0))
                                }
                            }
                            .frame(height: 4)
                            Text("\(row.2)")
                                .font(.system(size: 12.5))
                                .monospacedDigit()
                                .foregroundStyle(row.2 > 0 ? Color.wmLabel(scheme) : Color.wmFaint(scheme))
                                .frame(width: 26, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1).padding(.top, 6) }
            }
        }
    }

    /// Pierścień „zostało" — minimum 3 % wypełnienia, żeby pusty stan nie
    /// wyglądał na błąd. Na pierścieniu jest to, co ZOSTAŁO (jak w projekcie).
    private func ring<Content: View>(fraction: Double, color: Color, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Circle().stroke(Color.wmBarTrack(scheme), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.03, min(1, 1 - fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content()
        }
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
    }

    private func memberAvatar(userId: String, name: String) -> some View {
        Group {
            if let member = sessionStore.householdMembers.first(where: { $0.id == userId }) {
                MemberAvatar(member: member, members: sessionStore.householdMembers, size: 20)
            } else {
                Circle().fill(WMPalette.terracotta.opacity(0.15))
                    .overlay(Text(String(name.prefix(1)).uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(WMPalette.terracotta))
                    .frame(width: 20, height: 20)
            }
        }
    }

    // MARK: - Zasady

    private func rulesCard(_ usage: AgentUsageDTO) -> some View {
        AssistantSurfaceCard {
            AssistantSectionLabel(text: "Co się liczy")
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array([
                (true, "Liczy się: każda wysłana wiadomość, także „Zmień” i odpowiedzi na dopytanie."),
                (true, "Liczy się: każde „Dodaj do planu” — tydzień, dzień albo podmiana."),
                (false, "Nie liczy się: oglądanie propozycji, cofnięcie zapisu, tura przerwana błędem."),
            ].enumerated()), id: \.offset) { index, rule in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(rule.0 ? Color.wmSageTint(scheme) : Color.wmInsetSurface(scheme))
                        Image(systemName: rule.0 ? "checkmark" : "xmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(rule.0 ? WMPalette.sage : Color.wmFaint(scheme))
                    }
                    .frame(width: 20, height: 20)
                    Text(rule.1)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(alignment: .top) { if index > 0 { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) } }
            }
            Text(rulesFootnote(usage))
                .font(.system(size: 12.5))
                .lineSpacing(1.5)
                .foregroundStyle(Color.wmFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 13)
                .overlay(alignment: .top) { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) }
        }
    }

    private func rulesFootnote(_ usage: AgentUsageDTO) -> String {
        if usage.isTrial {
            return "Po wyczerpaniu darmowych wiadomości rozmowa się zatrzymuje, a zapisane plany zostają w Planie tygodnia. PRO daje pulę miesięczną dla całego domu."
        }
        if usage.plans.remaining == 0 {
            return "Pula planów wyczerpana: rozmowa działa dalej, blokuje się tylko „Dodaj do planu”. Wraca \(usage.resetsAt.map(Self.resetLabel) ?? "w nowym miesiącu")."
        }
        return "Po wyczerpaniu puli planów rozmowa działa dalej, blokuje się tylko „Dodaj do planu”. Nowy miesiąc odnawia oba liczniki."
    }

    // MARK: - Stopka

    private func footer(_ usage: AgentUsageDTO) -> some View {
        AssistantStickyFooter {
            if usage.isTrial {
                WMSoftButton(title: "Odblokuj PRO", leadingIcon: "sparkles", trailingIcon: nil) {
                    dismiss()
                    onUpgrade?()
                }
            } else if usage.showsManageSubscription {
                WMSoftButton(title: "Zarządzaj subskrypcją", trailingIcon: "arrow.up.right") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                }
            }
        }
    }

    /// „1 października” z ISO; sam napis ISO, gdy nie da się sparsować.
    static func resetLabel(_ iso: String) -> String {
        guard let date = AgentStore.parseTimestamp(iso) else { return iso }
        return resetFormatter.string(from: date)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()
}
