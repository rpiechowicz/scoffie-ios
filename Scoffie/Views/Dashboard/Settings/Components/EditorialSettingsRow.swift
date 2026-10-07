import SwiftUI

/// Wiersz w karcie listy — ten sam co lista w Filtrach (`RecipeFilterListRowLabel`,
/// 6.10.2026, artefakt „Ustawienia Scoffie”): płaski kafelek 30 pt
/// (`EditorialSettingsTileIcon`), tytuł 15 semibold, wartość 15 szara przed
/// strzałką / przełącznikiem, wiersz 52 pt, kreska od tytułu (12 + 30 + 12).
/// Dawny wiersz z makiety „settings.jsx” (`Row`: 14/16 pt, kafel 32 z gradientem,
/// tytuł 15,5, wartość 14) był o ~8 pt wyższy i inny niż reszta aplikacji.
struct EditorialSettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String? = nil
    var isLast: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowBody
                }
                .buttonStyle(.plain)
            } else {
                rowBody
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    // Kreska zaczyna się pod tytułem, nie pod kafelkiem.
                    .padding(.leading, 12 + 30 + 12)
            }
        }
    }

    private var rowBody: some View {
        HStack(spacing: 12) {
            EditorialSettingsTileIcon(icon: icon, color: iconColor)

            Text(title)
                .font(.sc(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.sc(size: 15))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
            }

            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

// Convenience initialisers — chevron is the default trailing accessory,
// matching the design's `onRight: 'chevron'` default.
extension EditorialSettingsRow where Trailing == EditorialSettingsChevron {
    init(
        icon: String,
        iconColor: Color,
        title: String,
        value: String? = nil,
        isLast: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.value = value
        self.isLast = isLast
        self.action = action
        self.trailing = { EditorialSettingsChevron() }
    }
}

/// Strzałka wiersza — ta sama co w liście Filtrów (11 pt bold, `scFaint`).
struct EditorialSettingsChevron: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.sc(size: 11, weight: .bold))
            .foregroundStyle(Color.scFaint(scheme))
    }
}
