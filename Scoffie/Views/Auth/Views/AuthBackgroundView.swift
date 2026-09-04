import SwiftUI

struct AuthBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.wmCanvas(colorScheme)
            .ignoresSafeArea()
    }
}

#Preview("Dark") {
    AuthBackgroundView()
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AuthBackgroundView()
        .preferredColorScheme(.light)
}
