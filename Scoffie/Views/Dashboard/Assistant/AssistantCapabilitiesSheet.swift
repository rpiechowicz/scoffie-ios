import SwiftUI

/// „Co potrafi asystent" — arkusz z menu ⋯ (pełna ściąga); przepływ
/// startowy pokazuje tylko 4 karty „Poznaj" i linkuje tutaj z ostatniej.
///
/// Trzy warstwy: jedna zasada w JEDNYM wierszu (piszesz → karta → decydujesz),
/// pięć grup umiejętności jako listy wierszy (tytuł + przykład, stuknięcie
/// WYSYŁA przykład — ekran pomocy kończy się pierwszą wiadomością, nie
/// czytaniem), zasady gry i prywatność. Limitów tu nie ma — to ekran „co",
/// nie „ile", i widzi go też ktoś, kto asystenta jeszcze nie włączył.
struct AssistantCapabilitiesSheet: View {
    let store: AgentStore
    /// Wysyła przykład jako wiadomość (arkusz sam się zamyka).
    let onAsk: (String) -> Void
    /// „Napisz do asystenta" — fokus na polu po zamknięciu.
    var onCompose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// Rozwinięty wiersz bez przykładu (zasady) — pokazuje opis i miniaturę.
    @State private var openId: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                SCPageBackground(scheme: scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialSheetHeader(eyebrow: "Asystent", title: "Co potrafi asystent") {
                            dismiss()
                        }

                        principle

                        ForEach(AssistantCapabilities.groups) { group in
                            groupCard(group)
                        }

                        rulesCard
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
    }

    // MARK: - Jedna zasada, jeden wiersz

    /// „Piszesz zdaniem → dostajesz kartę → Ty decydujesz” — kompaktowo,
    /// bez bohatera marketingowego: to jest instrukcja, nie reklama.
    private var principle: some View {
        HStack(spacing: 6) {
            principleStep("Piszesz zdaniem", icon: "text.cursor")
            principleArrow
            principleStep("Dostajesz kartę", icon: "rectangle.stack")
            principleArrow
            principleStep("Ty decydujesz", icon: "checkmark", filled: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: AssistantCardMetrics.radius, style: .continuous).fill(Color.scAccentTint(scheme)))
        .overlay(RoundedRectangle(cornerRadius: AssistantCardMetrics.radius, style: .continuous).stroke(SCPalette.terracotta.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Piszesz zdaniem, dostajesz kartę, Ty decydujesz")
    }

    private var principleArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.scFaint(scheme))
            .fixedSize()
    }

    private func principleStep(_ title: String, icon: String, filled: Bool = false) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(filled ? Color.scPageBase(scheme) : Color.scLabel(scheme))
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(filled ? SCPalette.terracotta : Color.scInsetSurface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(filled ? Color.clear : Color.scTileStroke(scheme), lineWidth: 1))
    }

    // MARK: - Grupy

    private func groupCard(_ group: AssistantCapabilities.Group) -> some View {
        AssistantSurfaceCard {
            HStack(alignment: .firstTextBaseline) {
                AssistantSectionLabel(text: group.label, color: group.accent.color)
                Spacer()
                Text(group.lead).font(.system(size: 11.5)).foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            ForEach(Array(group.items.enumerated()), id: \.element) { index, id in
                abilityRow(AssistantCapabilities.by(id), first: index == 0)
            }
        }
    }

    /// Wiersz umiejętności: tytuł + przykład. Z przykładem stuknięcie WYSYŁA
    /// go (strzałka w prawo-górę mówi, że coś się wyśle); bez przykładu
    /// rozwija opis z miniaturą.
    private func abilityRow(_ capability: AssistantCapability, first: Bool) -> some View {
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
                HStack(spacing: 12) {
                    AssistantIconTile(icon: capability.icon, accent: capability.accent, size: 34, radius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(capability.title)
                            .font(.system(size: 15.5, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        if let example = capability.example {
                            Text("„\(example)”")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.scMuted(scheme))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: sends ? "arrow.up.right" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(sends ? SCPalette.terracotta : Color.scFaint(scheme))
                        .rotationEffect(.degrees(!sends && open ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.985))
            .accessibilityHint(sends ? "Wysyła ten przykład do asystenta" : (open ? "Zwija opis" : "Rozwija opis"))
            .accessibilityAddTraits(open ? [.isSelected] : [])

            if open {
                VStack(alignment: .leading, spacing: 14) {
                    Text(capability.body)
                        .font(.system(size: 14.5))
                        .lineSpacing(3)
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let thumb = capability.thumb {
                        AssistantThumb(kind: thumb)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 18)
                .transition(.opacity)
            }
        }
        .background(open ? Color.black.opacity(scheme == .dark ? 0.18 : 0.03) : Color.clear)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.scRule(scheme)).frame(height: 1).padding(.leading, 62) }
        }
    }

    // MARK: - Zasady, prywatność

    private var rulesCard: some View {
        AssistantSurfaceCard {
            AssistantSectionLabel(text: "Zasady gry")
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            ForEach(Array(AssistantCapabilities.rules.enumerated()), id: \.element.id) { index, rule in
                infoRow(icon: rule.icon, accent: rule.accent, title: rule.title, detail: rule.detail, first: index == 0)
            }
        }
    }

    private var privacyCard: some View {
        AssistantSurfaceCard {
            AssistantSectionLabel(text: "Prywatność", color: SCPalette.sage)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            infoRow(icon: "checkmark.shield.fill", accent: .sage, title: "Nie idzie do modelu", detail: "Wzrost, waga, płeć, rok urodzenia, kroki, e-mail i hasło Cookidoo nigdy nie idą do modelu.", first: true)
            infoRow(icon: "person.2.fill", accent: .sage, title: "Domownicy tylko za zgodą", detail: "Dane innych osób trafiają do planu dopiero, gdy same włączą asystenta.", first: false)
            infoRow(icon: "lock.shield.fill", accent: .sage, title: "Zgodę cofniesz w menu", detail: "Rozmowy i notatki pamięci znikają, plan i przepisy zostają.", first: false)
        }
    }

    private func infoRow(icon: String, accent: AssistantAccent, title: String, detail: String, first: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AssistantIconTile(icon: icon, accent: accent, size: 32, radius: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).tracking(-0.25).foregroundStyle(Color.scLabel(scheme))
                Text(detail).font(.system(size: 13.5)).lineSpacing(2).foregroundStyle(Color.scMuted(scheme)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) } }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        AssistantStickyFooter {
            SCSoftButton(title: "Napisz do asystenta", trailingIcon: "arrow.up") {
                dismiss()
                onCompose?()
            }
        }
    }
}
