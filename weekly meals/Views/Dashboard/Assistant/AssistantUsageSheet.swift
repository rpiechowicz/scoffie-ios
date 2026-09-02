import SwiftUI

/// Limity asystenta — dwie pule, nie jedna.
///
/// Wiadomości i zapisane plany to osobne liczniki (projekt v2): wyczerpany
/// zapis nie blokuje rozmowy, więc pokazujemy obie belki osobno, z datą
/// odnowienia i rozkładem na domowników — pula jest wspólna dla domu
/// i ktoś zawsze pyta „kto to zużył”.
struct AssistantUsageSheet: View {
    let store: AgentStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var usage: AgentUsageDTO?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.wmCanvas(scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let usage {
                            Text(subtitle(for: usage))
                                .font(.system(size: 13.5))
                                .foregroundStyle(Color.wmMuted(scheme))
                                .fixedSize(horizontal: false, vertical: true)

                            QuotaBar(
                                icon: "sparkles",
                                label: "Wiadomości",
                                quota: usage.messages,
                                tint: WMPalette.terracotta,
                                note: messagesNote(usage)
                            )
                            QuotaBar(
                                icon: "calendar",
                                label: "Zapisane plany",
                                quota: usage.plans,
                                tint: WMPalette.butter,
                                note: plansNote(usage)
                            )

                            if let byUser = usage.byUser, !byUser.isEmpty {
                                perUser(byUser)
                            }
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
                    .padding(.horizontal, WMPageMetrics.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Limity asystenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            usage = await store.loadUsage()
            isLoading = false
        }
    }

    private func subtitle(for usage: AgentUsageDTO) -> String {
        let tier = usage.tier == "FREE" ? "Plan bezpłatny" : usage.tier
        return "\(tier) · wspólne dla całego domu · odnawiają się \(Self.resetLabel(usage.resetsAt))"
    }

    private func messagesNote(_ usage: AgentUsageDTO) -> String {
        usage.messages.remaining == 0
            ? "Pula wyczerpana · wraca \(Self.resetLabel(usage.resetsAt))"
            : "Zostało \(usage.messages.remaining)"
    }

    private func plansNote(_ usage: AgentUsageDTO) -> String {
        usage.plans.remaining == 0
            ? "Pula wyczerpana · rozmowa działa, zapis wróci \(Self.resetLabel(usage.resetsAt))"
            : "Zostało \(usage.plans.remaining)"
    }

    private func perUser(_ rows: [AgentUsageByUserDTO]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wiadomości na osobę")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Color.wmFaint(scheme))

            ForEach(rows) { row in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(WMPalette.terracotta.opacity(0.15))
                        Text(String(row.displayName.prefix(1)).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WMPalette.terracotta)
                    }
                    .frame(width: 24, height: 24)

                    Text(row.displayName)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.wmLabel(scheme))

                    Spacer(minLength: 8)

                    Text("\(row.messages)")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmLabel(scheme))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    /// „1 października” z ISO; sam napis ISO, gdy nie da się sparsować.
    private static func resetLabel(_ iso: String) -> String {
        guard let date = AgentStore.parseTimestamp(iso) else { return iso }
        return resetFormatter.string(from: date)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private struct QuotaBar: View {
        let icon: String
        let label: String
        let quota: AgentQuotaDTO
        let tint: Color
        let note: String

        @Environment(\.colorScheme) private var scheme

        private var isFull: Bool { quota.remaining == 0 }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmLabel(scheme))
                    Spacer(minLength: 8)
                    HStack(spacing: 2) {
                        Text("\(quota.used)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isFull ? tint : Color.wmLabel(scheme))
                        Text("/ \(quota.limit)")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.wmFaint(scheme))
                    }
                    .monospacedDigit()
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.wmBarTrack(scheme))
                        Capsule()
                            .fill(tint)
                            .frame(width: geometry.size.width * quota.fraction)
                    }
                }
                .frame(height: 6)

                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isFull ? tint : Color.wmFaint(scheme))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.wmCardSurface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.wmCardStroke(scheme), lineWidth: 1)
            )
        }
    }
}
