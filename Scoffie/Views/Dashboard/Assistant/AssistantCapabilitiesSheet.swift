import SwiftUI

/// „17 · Co potrafi asystent” — 1:1 z makietą: „Jedna zasada” jako
/// kompaktowa zasada onboardingu (Piszesz → Karta → Ty decydujesz), niżej
/// realne możliwości w grupach — każda z przykładem do wysłania jednym
/// dotknięciem. Stopka: „Napisz do asystenta”.
struct AssistantCapabilitiesSheet: View {
    let store: AgentStore
    /// Wysyła przykład jako wiadomość (arkusz sam się zamyka).
    let onAsk: (String) -> Void
    /// „Napisz do asystenta" — fokus na polu po zamknięciu.
    var onCompose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// Rozwinięty wiersz bez przykładu — pokazuje opis.
    @State private var openId: String?

    var body: some View {
        NavigationStack {
            AssistantSheetScaffold(
                title: "Co potrafi asystent",
                onClose: { dismiss() },
                footer: {
                    AssistantPrimaryButton(
                        action: AssistantCardAction(title: "Napisz do asystenta", icon: "arrow.right") {
                            dismiss()
                            onCompose?()
                        }
                    )
                }
            ) {
                ruleCard
                    .padding(.top, 10)

                // Jedno zdanie, które mówi, co robi stuknięcie w wiersz niżej:
                // przykład idzie od razu jako pierwsza wiadomość.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AssistantLook.terra(scheme))
                        .padding(.top, 1)
                    Text("Stuknij przykład, a wyślę go od razu — rozmowa zacznie się w tej samej chwili.")
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .accessibilityElement(children: .combine)

                ForEach(AssistantCapabilities.groups) { group in
                    AssistantGroup(title: group.label, aside: group.lead, titleColor: group.accent.color) {
                        ForEach(Array(group.items.enumerated()), id: \.element) { index, id in
                            abilityRow(AssistantCapabilities.by(id), accent: group.accent, first: index == 0)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Jedna zasada

    /// `RuleCard`: eyebrow „Jedna zasada” + „Planu nie zmienia sam”, tytuł
    /// „Piszesz zdaniem, dostajesz kartę”, trzy pigułki z chevronami.
    private var ruleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Jedna zasada")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(AssistantLook.terra(scheme))
                Spacer(minLength: 10)
                Text("Planu nie zmienia sam")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .lineLimit(1)
            }

            Text("Piszesz zdaniem, dostajesz kartę")
                .font(.system(size: 16, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(AssistantLook.ink(scheme))
                .padding(.top, 4)

            HStack(spacing: 3) {
                ruleStep("Piszesz", icon: "arrow.up")
                ruleArrow
                ruleStep("Karta", icon: nil)
                ruleArrow
                ruleStep("Ty decydujesz", icon: "checkmark", filled: true)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AssistantLook.terraFill(scheme).opacity(scheme == .dark ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AssistantLook.terraFill(scheme).opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jedna zasada: piszesz zdaniem, dostajesz kartę, Ty decydujesz. Planu nie zmienia sam.")
    }

    private var ruleArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(AssistantLook.ink(scheme).opacity(0.35))
            .fixedSize()
    }

    private func ruleStep(_ title: String, icon: String?, filled: Bool = false) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            } else {
                SCMarkShape()
                    .fill(AssistantLook.terraFill(scheme))
                    .frame(width: 12, height: 12)
            }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .tracking(-0.2)
        .foregroundStyle(filled ? Color.white : AssistantLook.ink(scheme))
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(Capsule().fill(filled ? AssistantLook.terra(scheme) : AssistantLook.field(scheme)))
        .overlay(Capsule().stroke(filled ? Color.clear : AssistantLook.cardStroke(scheme), lineWidth: 1))
    }

    // MARK: - Wiersze

    /// Wiersz umiejętności: kafelek ikony · tytuł · „przykład” w terakocie
    /// · kropka z strzałką (wysyła). Bez przykładu: rozwija opis.
    private func abilityRow(_ capability: AssistantCapability, accent: AssistantAccent, first: Bool) -> some View {
        let open = openId == capability.id
        let sends = capability.example != nil
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if let example = capability.example {
                    dismiss()
                    onAsk(example)
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        openId = open ? nil : capability.id
                    }
                }
            } label: {
                AssistantRow(
                    title: capability.title,
                    subtitle: capability.example.map { "„\($0)”" } ?? capability.body,
                    chevron: !sends,
                    first: first,
                    titleSize: 15,
                    subtitleColor: sends ? AssistantLook.terra(scheme) : nil,
                    subtitleWeight: sends ? .medium : .regular,
                    verticalPadding: 10,
                    leadingInset: 12,
                    trailingInset: 12,
                    leading: { AssistantTile(icon: capability.icon, tint: accent.tint(scheme), color: accent.color) },
                    trailing: {
                        if sends {
                            ZStack {
                                Circle().fill(AssistantLook.terraTint(scheme))
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AssistantLook.terra(scheme))
                            }
                            .frame(width: 30, height: 30)
                        }
                    }
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.985))
            .accessibilityHint(sends ? "Wysyła ten przykład do asystenta" : (open ? "Zwija opis" : "Rozwija opis"))

            if open {
                VStack(alignment: .leading, spacing: 14) {
                    Text(capability.body)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let thumb = capability.thumb {
                        AssistantThumb(kind: thumb)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
    }
}
