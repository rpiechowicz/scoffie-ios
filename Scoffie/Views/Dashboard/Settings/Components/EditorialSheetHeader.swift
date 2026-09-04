import SwiftUI

// Editorial sheet header used by every Ustawienia sheet (Gospodarstwo,
// Preferencje, Dieta, Pomoc). Mirrors the pattern from Produkty's history
// + archive-preview sheets — small uppercase eyebrow in terracotta, heavy
// title in label color, circular xmark close button on the trailing edge.
struct EditorialSheetHeader: View {
    let eyebrow: String
    let title: String
    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(WMPalette.terracotta)
                    .lineLimit(1)

                Text(title)
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.wmChipBg(scheme)))
                    .overlay(Circle().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zamknij")
        }
    }
}

// Small editorial label above a single card — same look as the
// `EditorialSettingsSectionHeader` used on the main settings list, kept
// as a separate component so the sheet content can tune padding without
// inheriting the list's `marginTop: 20` baseline.
struct EditorialSheetSectionLabel: View {
    let title: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Color.wmFaint(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
    }
}
