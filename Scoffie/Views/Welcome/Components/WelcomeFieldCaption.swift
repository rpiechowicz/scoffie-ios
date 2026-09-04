import SwiftUI

// Tiny "FORM SECTION" caption used above each input card on the welcome
// flow. Mirrors the design's tracked, uppercase footnote.
struct WelcomeFieldCaption: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Color.wmFaint(colorScheme))
            .padding(.horizontal, 6)
    }
}
