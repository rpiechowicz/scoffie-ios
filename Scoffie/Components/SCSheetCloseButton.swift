import SwiftUI

/// Krążek z krzyżykiem, którym zamyka się KAŻDY arkusz w aplikacji.
///
/// Jeden rysunek, jedno miejsce. Wcześniej ten sam przycisk stał w czterech
/// plikach w czterech wariantach: 32, 34 i dwa razy 36 punktów, raz na
/// `scChipBg`, raz na `scTileBg`, raz na `scFeatureRowBg`. Różnice nie brały
/// się z niczego poza kolejnością pisania ekranów, a zamykanie arkusza jest
/// pierwszą rzeczą, jakiej szuka ręka — i nie ma prawa wyglądać inaczej
/// zależnie od tego, skąd się przyszło.
///
/// Strzałki „wstecz” tu nie ma i nie będzie: arkusz się ZAMYKA, a nie cofa.
/// Nawet gdy arkusze stoją jeden na drugim, krzyżyk zdejmuje wierzchni —
/// tak samo, jak zdejmuje go przeciągnięcie w dół.
struct SCSheetCloseButton: View {
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.scMuted(scheme))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.scChipBg(scheme)))
                .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.9))
        .accessibilityLabel("Zamknij")
    }
}

#Preview("SCSheetCloseButton") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        SCSheetCloseButton {}
    }
    .preferredColorScheme(.dark)
}
