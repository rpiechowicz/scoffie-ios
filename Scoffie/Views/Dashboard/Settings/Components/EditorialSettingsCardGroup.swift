import SwiftUI

// Grouped settings card on Ustawienia v2 — rounded 18pt container with
// the warm tile background, soft border and `overflow: hidden` so the
// row hairlines tuck inside the corner radius. Source: settings.jsx →
// `CardGroup`.
//
// Rows are passed in via a `@ViewBuilder` so a card can mix custom
// content with the standard `EditorialSettingsRow` (e.g. the profile
// header or the "Wersja" row that uses the small "i" tile instead of
// the gradient TileIcon).
struct EditorialSettingsCardGroup<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// Section header above a card group — small uppercase label, dim color.
// Source: settings.jsx → `SectionHeader`.
//   `padding: '0 6px 8px', marginTop: 20`. 11pt 600 tracking 0.7 dim.
struct EditorialSettingsSectionHeader: View {
    let title: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Color.wmFaint(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}
