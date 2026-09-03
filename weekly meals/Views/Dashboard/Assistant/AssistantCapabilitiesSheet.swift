import SwiftUI

/// „Co potrafi asystent" — ostatni krok przepływu startowego (inline),
/// a potem arkusz z menu ⋯ i z ostatniej karty onboardingu. Trzy warstwy: jedna zasada (piszesz → karta → dodajesz),
/// cztery grupy umiejętności jako akordeony (wszystkie zwinięte na start),
/// zasady gry i prywatność. Limitów tu nie ma — to ekran „co", nie „ile",
/// i widzi go też ktoś, kto asystenta jeszcze nie włączył. Przykład
/// w rozwiniętym wierszu jest przyciskiem: ekran pomocy kończy się pierwszą
/// wiadomością, nie czytaniem.
struct AssistantCapabilitiesSheet: View {
    enum Presentation {
        /// Arkusz z menu ⋯ — własny nagłówek, „Napisz do asystenta".
        case sheet
        /// Ostatni krok przepływu startowego w zakładce: tytuł strony,
        /// wskaźnik kroków, „Napisz pierwszą wiadomość".
        case inline
    }

    let store: AgentStore
    var presentation: Presentation = .sheet
    /// Wysyła przykład jako wiadomość (arkusz sam się zamyka).
    let onAsk: (String) -> Void
    /// „Napisz do asystenta" — fokus na polu po zamknięciu.
    var onCompose: (() -> Void)? = nil
    /// „Wstecz" do ostatniej karty „Poznaj" (tylko inline).
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var openId: String?

    var body: some View {
        switch presentation {
        case .sheet:
            NavigationStack {
                content
                    .toolbar(.hidden, for: .navigationBar)
            }
            .presentationDragIndicator(.visible)
        case .inline:
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if presentation == .sheet {
                    WMPageBackground(scheme: scheme).ignoresSafeArea()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if presentation == .sheet {
                            EditorialSheetHeader(eyebrow: "Asystent AI", title: "Co potrafi asystent") {
                                dismiss()
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                AssistantSectionLabel(text: "Asystent AI", color: WMPalette.terracotta)
                                Text("Co potrafi asystent")
                                    .font(.system(size: 26, weight: .bold))
                                    .tracking(-0.6)
                                    .foregroundStyle(Color.wmLabel(scheme))
                                Text("Zgoda zapisana. Każdy przykład poniżej możesz od razu wysłać — resztę asystent dopyta.")
                                    .font(.system(size: 13.5))
                                    .lineSpacing(2)
                                    .foregroundStyle(Color.wmMuted(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        heroRule

                        ForEach(AssistantCapabilities.groups) { group in
                            groupCard(group)
                        }

                        rulesCard
                        privacyCard
                    }
                    .padding(.horizontal, presentation == .sheet ? 20 : WMPageMetrics.horizontal)
                    .padding(.top, presentation == .sheet ? 18 : 4)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)

                footer
            }
        }
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

            // Trzy równe pola z „Dodaj do planu" ucinały tekst na węższych
            // ekranach — etykiety są krótkie, a chip bierze tyle, ile potrzebuje.
            HStack(spacing: 6) {
                ruleStep("Piszesz", icon: "arrow.up", filled: false)
                ruleArrow
                ruleStep("Karta", icon: "rectangle.stack", filled: false)
                ruleArrow
                ruleStep("Dodajesz", icon: "checkmark", filled: true)
            }
            .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.wmAccentTint(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(WMPalette.terracotta.opacity(0.28), lineWidth: 1))
    }

    private var ruleArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.wmFaint(scheme))
            .fixedSize()
    }

    private func ruleStep(_ title: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
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
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

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
                HStack(spacing: 12) {
                    AssistantIconTile(icon: capability.icon, accent: capability.accent, size: 34, radius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(capability.title)
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.wmLabel(scheme))
                        if !open, let example = capability.example {
                            Text("„\(example)”")
                                .font(.system(size: 13))
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
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? [.isSelected] : [])

            if open {
                VStack(alignment: .leading, spacing: 14) {
                    Text(capability.body)
                        .font(.system(size: 14.5))
                        .lineSpacing(3)
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
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 18)
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
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            ForEach(Array(AssistantCapabilities.rules.enumerated()), id: \.element.id) { index, rule in
                infoRow(icon: rule.icon, accent: rule.accent, title: rule.title, detail: rule.detail, first: index == 0)
            }
        }
    }

    private var privacyCard: some View {
        AssistantSurfaceCard {
            AssistantSectionLabel(text: "Prywatność", color: WMPalette.sage)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            infoRow(icon: "checkmark.shield.fill", accent: .sage, title: "Zostaje w telefonie", detail: "Wzrost, waga, płeć, rok urodzenia, kroki, e-mail i hasło Cookidoo nigdy nie idą do modelu.", first: true)
            infoRow(icon: "person.2.fill", accent: .sage, title: "Domownicy tylko za zgodą", detail: "Dane innych osób trafiają do planu dopiero, gdy same włączą asystenta.", first: false)
            infoRow(icon: "lock.shield.fill", accent: .sage, title: "Zgodę cofniesz w menu", detail: "Rozmowy i notatki pamięci znikają, plan i przepisy zostają.", first: false)
        }
    }

    private func infoRow(icon: String, accent: AssistantAccent, title: String, detail: String, first: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AssistantIconTile(icon: icon, accent: accent, size: 32, radius: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).tracking(-0.25).foregroundStyle(Color.wmLabel(scheme))
                Text(detail).font(.system(size: 13.5)).lineSpacing(2).foregroundStyle(Color.wmMuted(scheme)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) } }
    }

    private var footer: some View {
        AssistantStickyFooter {
            if presentation == .inline {
                WelcomeStepper(step: AssistantIntroSteps.capabilities, total: AssistantIntroSteps.total)
                    .padding(.bottom, 8)
            }
            HStack(spacing: 10) {
                if presentation == .inline, let onBack {
                    WMSoftIconButton(systemName: "chevron.left", accessibilityLabel: "Wstecz", action: onBack)
                }
                WMSoftButton(
                    title: presentation == .sheet ? "Napisz do asystenta" : "Napisz pierwszą wiadomość",
                    leadingIcon: "sparkles"
                ) {
                    dismiss()
                    onCompose?()
                }
            }
        }
    }
}
