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
///
/// 7.10.2026 (Rafał: „popraw widoki i sheet dla asystenta zgodnie z nowym
/// design”): lista na klockach Ustawień — etykieta sekcji
/// (`EditorialSheetSectionLabel`), karta (`EditorialSettingsCardGroup`)
/// i wiersz (`EditorialSettingsRow` z pełnym kafelkiem w kolorze grupy
/// i przykładem w podpisie). Dawne `AssistantGroup` z kolorowym tytułem
/// i dopiskiem po prawej („Najczęściej”, „Z planu do sklepu”) oraz
/// `AssistantRow` z kafelkiem w tincie odpadły — dopiski nic nie mówiły.
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
                // Glif „Co potrafi Asystent” z menu ⋯.
                icon: "rectangle.stack.fill",
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(AssistantCapabilities.groups.enumerated()), id: \.element.id) { index, group in
                        EditorialSheetSectionLabel(title: group.label)
                            .padding(.top, index == 0 ? 14 : 20)
                        EditorialSettingsCardGroup {
                            ForEach(Array(group.items.enumerated()), id: \.element) { itemIndex, id in
                                abilityRow(
                                    AssistantCapabilities.by(id),
                                    color: group.accent.color,
                                    isLast: itemIndex == group.items.count - 1
                                )
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Wiersze

    /// Wiersz umiejętności: kafelek w kolorze grupy · tytuł · przykład
    /// w cudzysłowie (cały, bez ucinania — to cała wiadomość, widać ją,
    /// zanim pójdzie) · strzałka „wyślij” w terakocie.
    private func abilityRow(_ capability: AssistantCapability, color: Color, isLast: Bool) -> some View {
        EditorialSettingsRow(
            icon: capability.icon,
            iconColor: color,
            title: capability.title,
            subtitle: "„\(capability.example)”",
            isLast: isLast,
            wrapsText: true,
            action: {
                dismiss()
                onAsk(capability.example)
            }
        ) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.sc(size: 22, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("\(capability.title): \(capability.example)")
        .accessibilityHint("Wysyła ten przykład do Asystenta")
    }
}
