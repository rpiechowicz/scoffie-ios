import SwiftUI

// Tiny "FORM SECTION" caption used above each input card on the welcome
// flow. Mirrors the design's tracked, uppercase footnote.
// Krój ten sam co `EditorialSheetSectionLabel` (10,5 pt bold, tracking 1,4)
// — kreator i arkusze Ustawień pytają o te same rzeczy i podpisują je
// jedną etykietą.
struct WelcomeFieldCaption: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Color.scFaint(colorScheme))
            .padding(.horizontal, 6)
    }
}
