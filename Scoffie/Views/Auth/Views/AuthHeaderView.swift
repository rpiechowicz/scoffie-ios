import SwiftUI

struct AuthHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Spacingi z designu: paddingTop 4 nad title, 12pt do subtitle
        // (via VStack spacing). Subtitle→features 24pt dodawane w AuthView.
        VStack(alignment: .leading, spacing: 12) {
            title
            Text("Plan posiłków, lista zakupów i zdrowe pomysły na cały tydzień — w jednej aplikacji.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.wmMuted(colorScheme))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: some View {
        // „Gotujcie razem, planujcie raz." — „razem" italic + terracotta.
        // lineSpacing 8 = lineHeight 40 na fontSize 32 (jak w designie).
        (
            Text("Gotujcie ")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.wmLabel(colorScheme))
            + Text("razem")
                .font(.system(size: 32, weight: .medium).italic())
                .foregroundStyle(WMPalette.terracotta)
            + Text(", planujcie raz.")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.wmLabel(colorScheme))
        )
        .lineSpacing(8)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Dark") {
    AuthHeaderView()
        .padding()
        .background(Color.wmCanvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AuthHeaderView()
        .padding()
        .background(Color.wmCanvas(.light))
        .preferredColorScheme(.light)
}
