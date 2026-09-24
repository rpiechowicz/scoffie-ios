import SwiftUI

/// Menu ⋯ → „Co potrafi Asystent” — realne możliwości w grupach po tym, co
/// się ROBI (planuje, liczy, kupuje, gotuje, dzieli na dom), każda
/// z przykładem, który stuknięciem idzie od razu jako wiadomość. Stopka:
/// „Napisz do Asystenta”.
///
/// Od wprowadzenia v2 (24.09.2026) bez karty „Jedna zasada” (Piszesz →
/// Karta → Ty decydujesz) — to jest teraz krok „Ty decydujesz” wprowadzenia
/// i „Jak działa” — i bez akapitu instrukcji: to, że wiersz wysyła, mówi
/// jedno zdanie pod tytułem i strzałka przy każdym wierszu.
struct AssistantCapabilitiesSheet: View {
    let store: AgentStore
    /// Wysyła przykład jako wiadomość (arkusz sam się zamyka).
    let onAsk: (String) -> Void
    /// „Napisz do Asystenta" — fokus na polu po zamknięciu. Klawiatura
    /// wysuwa się tu, bo ktoś o nią poprosił.
    var onCompose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            AssistantSheetScaffold(
                eyebrow: "Asystent",
                title: "Co potrafi",
                subtitle: "Stuknij przykład — Asystent od razu się nim zajmie.",
                onClose: { dismiss() },
                footer: {
                    EditorialPrimaryActionButton(
                        title: "Napisz do Asystenta",
                        icon: "square.and.pencil",
                        action: {
                            dismiss()
                            onCompose?()
                        }
                    )
                }
            ) {
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

    // MARK: - Wiersze

    /// Wiersz umiejętności: kafelek ikony · tytuł · przykład w cudzysłowie
    /// w terakocie · krążek ze strzałką (wysyła).
    private func abilityRow(_ capability: AssistantCapability, accent: AssistantAccent, first: Bool) -> some View {
        Button {
            dismiss()
            onAsk(capability.example)
        } label: {
            AssistantRow(
                title: capability.title,
                subtitle: "„\(capability.example)”",
                chevron: false,
                first: first,
                titleSize: 15,
                subtitleColor: AssistantLook.terra(scheme),
                subtitleWeight: .medium,
                // Przykład to cała wiadomość — widać ją w całości, zanim
                // pójdzie, zamiast uciętej w pół zdania.
                subtitleWraps: true,
                verticalPadding: 10,
                leadingInset: 12,
                trailingInset: 12,
                leading: { AssistantTile(icon: capability.icon, tint: accent.tint(scheme), color: accent.color) },
                trailing: {
                    ZStack {
                        Circle().fill(AssistantLook.terraTint(scheme))
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AssistantLook.terra(scheme))
                    }
                    .frame(width: 30, height: 30)
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityLabel("\(capability.title): \(capability.example)")
        .accessibilityHint("Wysyła ten przykład do Asystenta")
    }
}
