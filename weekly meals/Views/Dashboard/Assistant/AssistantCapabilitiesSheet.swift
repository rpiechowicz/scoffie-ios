import SwiftUI

/// „Co potrafi asystent" — arkusz z menu ⋯, z bramki zgody i z ostatniej
/// karty onboardingu. Trzy warstwy: jedna zasada (piszesz → karta → dodajesz),
/// cztery grupy umiejętności jako akordeony, zasady gry, limity domu
/// i prywatność. Przykład w rozwiniętym wierszu jest przyciskiem: ekran
/// pomocy kończy się pierwszą wiadomością, nie czytaniem.
struct AssistantCapabilitiesSheet: View {
    let store: AgentStore
    /// Wysyła przykład jako wiadomość (arkusz sam się zamyka).
    let onAsk: (String) -> Void
    /// „Napisz do asystenta" — fokus na polu po zamknięciu.
    var onCompose: (() -> Void)? = nil
    var onShowLimits: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var openId: String? = "week"
    @State private var usage: AgentUsageDTO?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WMPageBackground(scheme: scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        EditorialSheetHeader(eyebrow: "Asystent AI", title: "Co potrafi asystent") {
                            dismiss()
                        }

                        heroRule

                        ForEach(AssistantCapabilities.groups) { group in
                            groupCard(group)
                        }

                        rulesCard
                        limitsCard
                        privacyCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)

                footer
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .task { usage = await store.loadUsage() }
    }

    // MARK: - Jedna zasada

    private var heroRule: some View {
        VStack(alignment: .leading, spacing: 6) {
            AssistantSectionLabel(text: "Jedna zasada", color: WMPalette.terracotta)
            Text("Piszesz zdaniem, dostajesz kartę")
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.wmLabel(scheme))
            Text("Asystent zna dietę, alergeny i cele domu, ale planu nie zmienia sam. Każda propozycja przychodzi jako karta — Ty ją dodajesz.")
                .font(.system(size: 13.5))
                .lineSpacing(2)
                .foregroundStyle(Color.wmMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ruleStep("Piszesz", icon: "arrow.up", filled: false)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.wmFaint(scheme))
                ruleStep("Karta", icon: "rectangle.stack", filled: false)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.wmFaint(scheme))
                ruleStep("Dodaj do planu", icon: "checkmark", filled: true)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.wmAccentTint(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(WMPalette.terracotta.opacity(0.28), lineWidth: 1))
    }

    private func ruleStep(_ title: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(title).font(.system(size: 11.5, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(filled ? Color.wmPageBase(scheme) : Color.wmLabel(scheme))
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(filled ? WMPalette.terracotta : Color.wmInsetSurface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(filled ? Color.clear : Color.wmTileStroke(scheme), lineWidth: 1))
    }

    // MARK: - Grupy (akordeon)

    private func groupCard(_ group: AssistantCapabilities.Group) -> some View {
        AssistantSurfaceCard {
            HStack(alignment: .firstTextBaseline) {
                AssistantSectionLabel(text: group.label, color: group.accent.color)
                Spacer()
                Text(group.lead).font(.system(size: 11.5)).foregroundStyle(Color.wmFaint(scheme))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            ForEach(Array(group.items.enumerated()), id: \.element) { index, id in
                abilityRow(AssistantCapabilities.by(id), first: index == 0)
            }
        }
    }

    private func abilityRow(_ capability: AssistantCapability, first: Bool) -> some View {
        let open = openId == capability.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    openId = open ? nil : capability.id
                }
            } label: {
                HStack(spacing: 11) {
                    AssistantIconTile(icon: capability.icon, accent: capability.accent, size: 30, radius: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(capability.title)
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.wmLabel(scheme))
                        if !open, let example = capability.example {
                            Text("„\(example)”")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.wmMuted(scheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.wmFaint(scheme))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? [.isSelected] : [])

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    Text(capability.body)
                        .font(.system(size: 13.5))
                        .lineSpacing(2)
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let example = capability.example {
                        AssistantExampleBubble(text: example) {
                            dismiss()
                            onAsk(example)
                        }
                    }
                    if let thumb = capability.thumb {
                        AssistantThumb(kind: thumb)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(open ? Color.black.opacity(scheme == .dark ? 0.18 : 0.03) : Color.clear)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) }
        }
    }

    // MARK: - Zasady, limity, prywatność

    private var rulesCard: some View {
        AssistantSurfaceCard {
            AssistantSectionLabel(text: "Zasady gry")
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ForEach(Array(AssistantCapabilities.rules.enumerated()), id: \.element.id) { index, rule in
                infoRow(icon: rule.icon, accent: rule.accent, title: rule.title, detail: rule.detail, first: index == 0)
            }
        }
    }

    private var limitsCard: some View {
        AssistantSurfaceCard {
            HStack(alignment: .firstTextBaseline) {
                AssistantSectionLabel(text: "Limity domu", color: WMPalette.indigo)
                Spacer()
                if let usage {
                    Text("odnowienie \(AssistantUsageSheet.resetLabel(usage.resetsAt))")
                        .font(.system(size: 11.5)).foregroundStyle(Color.wmFaint(scheme))
                }
            }
            .padding(.horizontal, 14).padding(.top, 12)

            HStack(spacing: 14) {
                meter(n: usage?.messages.used ?? 0, of: usage?.messages.limit ?? 0, label: "wiadomości w tym miesiącu", color: WMPalette.terracotta)
                Rectangle().fill(Color.wmRule(scheme)).frame(width: 1)
                meter(n: usage?.plans.used ?? 0, of: usage?.plans.limit ?? 0, label: "zapisanych planów", color: WMPalette.sage)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .redacted(reason: usage == nil ? .placeholder : [])

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.2.fill").font(.system(size: 12, weight: .semibold))
                Text("Pula wspólna dla całego domu. Oglądanie propozycji nie zużywa planów — tylko „Dodaj do planu”.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Color.wmMuted(scheme))
            .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 11)
            .overlay(alignment: .top) { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) }
        }
    }

    private func meter(n: Int, of total: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(n)").font(.system(size: 26, weight: .bold)).tracking(-0.8).monospacedDigit().foregroundStyle(Color.wmLabel(scheme))
                Text("z \(total)").font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Color.wmMuted(scheme))
            }
            Text(label).font(.system(size: 12)).foregroundStyle(Color.wmMuted(scheme))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.wmBarTrack(scheme))
                    Capsule().fill(color).frame(width: geometry.size.width * (total > 0 ? min(1, Double(n) / Double(total)) : 0))
                }
            }
            .frame(height: 5)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var privacyCard: some View {
        AssistantSurfaceCard {
            AssistantSectionLabel(text: "Prywatność", color: WMPalette.sage)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            infoRow(icon: "checkmark.shield.fill", accent: .sage, title: "Zostaje w telefonie", detail: "Wzrost, waga, płeć, rok urodzenia, kroki, e-mail i hasło Cookidoo nigdy nie idą do modelu.", first: true)
            infoRow(icon: "person.2.fill", accent: .sage, title: "Domownicy tylko za zgodą", detail: "Dane innych osób trafiają do planu dopiero, gdy same włączą asystenta.", first: false)
            infoRow(icon: "lock.shield.fill", accent: .sage, title: "Zgodę cofniesz w menu", detail: "Rozmowy i notatki pamięci znikają, plan i przepisy zostają.", first: false)
        }
    }

    private func infoRow(icon: String, accent: AssistantAccent, title: String, detail: String, first: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            AssistantIconTile(icon: icon, accent: accent, size: 28, radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).tracking(-0.25).foregroundStyle(Color.wmLabel(scheme))
                Text(detail).font(.system(size: 12.5)).lineSpacing(1.5).foregroundStyle(Color.wmMuted(scheme)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) } }
    }

    private var footer: some View {
        AssistantStickyFooter {
            WMSoftButton(title: "Napisz do asystenta", leadingIcon: "sparkles") {
                dismiss()
                onCompose?()
            }
            if let onShowLimits {
                AssistantTextButton(title: "Zobacz limity") {
                    dismiss()
                    onShowLimits()
                }
            }
        }
        .padding(.bottom, 12)
    }
}
