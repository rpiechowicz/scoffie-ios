import SwiftUI

// One row inside a settings card group. Source: settings.jsx → `Row`.
//   Container — `padding: '14px 16px', gap: 14`, hairline below except last.
//   Tile icon (left) — 32pt rounded gradient square with white SF symbol.
//   Title — 15.5pt 600 label color.
//   Optional value — 14pt muted, sits before the chevron / toggle.
//   Right accessory — chevron (default), Toggle, custom view, or none.
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
                    .fill(Color.wmRule(scheme))
                    .frame(height: 1)
                    // Indent matches the icon width + gap so the rule
                    // visually starts under the title, not the tile.
                    .padding(.leading, 16 + 32 + 14)
            }
        }
    }

    private var rowBody: some View {
        HStack(spacing: 14) {
            EditorialSettingsTileIcon(icon: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .lineLimit(1)
            }

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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

// Right-side chevron — 14pt, 35% / 30% opacity. Source: settings.jsx →
// `RowChevron`.
struct EditorialSettingsChevron: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(
                scheme == .dark
                ? WMPalette.labelDark.opacity(0.35)
                : WMPalette.labelLight.opacity(0.30)
            )
    }
}
