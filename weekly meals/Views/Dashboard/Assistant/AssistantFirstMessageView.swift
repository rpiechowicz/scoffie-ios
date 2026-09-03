import SwiftUI

/// Ostatni krok przepływu startowego — „Od czego zaczniemy?". Cztery strony,
/// po jednej na grupę umiejętności (plan → cel i makro → dom → zakupy
/// i przepisy). Każda umiejętność to pełna wymiana: Twoje zdanie, odpowiedź
/// asystenta i karta, którą dostaniesz — stuknięcie w zdanie wysyła je jako
/// pierwszą wiadomość. Zasad gry i prywatności tu nie ma (były w kartach
/// „Poznaj"); pełna ściąga zostaje pod menu ⋯ → „Co potrafi asystent".
struct AssistantFirstMessageView: View {
    /// Stuknięty przykład — wysyłany jako pierwsza wiadomość.
    let onAsk: (String) -> Void
    /// „Napisz własną wiadomość" / „Pomiń" — rozmowa z fokusem na polu.
    let onCompose: () -> Void
    /// „Wstecz" z pierwszej strony — do ostatniej karty „Poznaj".
    let onBack: () -> Void
    var startPage = 0
    var onPageChange: ((Int) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @State private var page = 0

    private let groups = AssistantCapabilities.groups
    private var isLast: Bool { page == groups.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            AssistantIntroNavRow(trailingTitle: "Pomiń", onTrailing: onCompose)

            GeometryReader { proxy in
                TabView(selection: $page) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        ScrollView {
                            groupPage(group, first: index == 0, minHeight: max(0, proxy.size.height - 18))
                                .padding(.horizontal, WMPageMetrics.horizontal)
                                .padding(.top, 6)
                                .padding(.bottom, 12)
                        }
                        .scrollIndicators(.hidden)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            AssistantStickyFooter {
                WelcomeStepper(step: AssistantIntroSteps.firstMessagePage(page), total: AssistantIntroSteps.total)
                    .padding(.bottom, 8)

                HStack(spacing: 10) {
                    WMSoftIconButton(systemName: "chevron.left", accessibilityLabel: "Wstecz") {
                        if page > 0 { withAnimation { page -= 1 } } else { onBack() }
                    }
                    WMSoftButton(
                        title: isLast ? "Napisz własną wiadomość" : "Dalej",
                        leadingIcon: isLast ? "sparkles" : nil,
                        trailingIcon: isLast ? nil : "chevron.right"
                    ) {
                        if isLast { onCompose() } else { withAnimation { page += 1 } }
                    }
                }
            }
        }
        .onAppear { page = min(max(0, startPage), groups.count - 1) }
        .onChange(of: page) { _, value in onPageChange?(value) }
    }

    private func groupPage(_ group: AssistantCapabilities.Group, first: Bool, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                AssistantSectionLabel(text: first ? "Od czego zaczniemy?" : group.label, color: group.accent.color)
                Text(first ? group.label : group.lead)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(first
                    ? "\(group.lead). Pod każdym zdaniem widzisz, co odpowie asystent — stuknij zdanie, żeby zacząć od niego."
                    : "Stuknij zdanie, żeby zacząć od niego.")
                    .font(.system(size: 14.5))
                    .lineSpacing(3)
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element) { index, id in
                    abilityRow(AssistantCapabilities.by(id), first: index == 0)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.wmTileBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.wmTileStroke(scheme), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.06), radius: 12, y: 8)
    }

    /// Umiejętność bez akordeonu: tytuł, jedno zdanie i przykład do wysłania.
    private func abilityRow(_ capability: AssistantCapability, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AssistantIconTile(icon: capability.icon, accent: capability.accent, size: 40, radius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(capability.title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                    Text(capability.body)
                        .font(.system(size: 13.5))
                        .lineSpacing(2)
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let example = capability.example {
                AssistantExchangePreview(example: example, reply: capability.reply, thumb: capability.thumb) {
                    onAsk(example)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) }
        }
    }
}
