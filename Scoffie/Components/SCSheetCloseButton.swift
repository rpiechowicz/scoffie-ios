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
    /// Krzyżyk stoi na zdjęciu, a nie na tle arkusza — patrz
    /// `SCSheetIconButton.onImage`.
    var onImage: Bool = false
    var action: () -> Void

    var body: some View {
        SCSheetIconButton(systemName: "xmark", accessibilityLabel: "Zamknij", onImage: onImage, action: action)
    }
}

/// Ten sam krążek co krzyżyk arkusza, z dowolnym glifem.
///
/// Dla akcji, które stoją OBOK krzyżyka i mają wyglądać jak on — np. serce
/// w szczegółach posiłku. `tint` barwi sam glif (ulubione w terakocie);
/// tło i obwódka zostają te same, żeby para przycisków czytała się jako
/// jeden komplet.
struct SCSheetIconButton: View {
    let systemName: String
    var tint: Color? = nil
    let accessibilityLabel: String
    /// Przycisk stoi na zdjęciu (szczegóły posiłku). Zwykłe tło krążka to
    /// kilka procent krycia — na tle arkusza wystarcza, ale na jasnym kadrze
    /// krążek znikał. Tu dostaje kryjące tło arkusza pod szkłem i miękki
    /// cień; rozmiar, glif i obwódka zostają te same.
    var onImage: Bool = false
    /// Praca w toku — kręciołek w krążku (patrz `SCSheetIconLabel.isBusy`).
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SCSheetIconLabel(systemName: systemName, tint: tint, onImage: onImage, isBusy: isBusy)
        }
        .buttonStyle(PlanPressStyle(scale: 0.9))
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Sam krążek `SCSheetIconButton` — bez przycisku wokół.
///
/// Dla kontrolek, które nie są zwykłym `Button`, a mają stać w tym samym
/// komplecie: `Menu` („Udostępnij” / „Wyłącz link” w szczegółach przepisu)
/// rysuje ten sam krążek jako swoją etykietę, zamiast drugiej kopii rysunku.
struct SCSheetIconLabel: View {
    let systemName: String
    var tint: Color? = nil
    var onImage: Bool = false
    /// Praca w toku (np. pobieranie linku) — kręciołek w miejscu glifu,
    /// krążek zostaje ten sam, więc sąsiedzi nie drgną.
    var isBusy: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let glyph = tint ?? (onImage ? Color.scLabel(scheme) : Color.scMuted(scheme))
        Group {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(glyph)
                    .transition(.opacity)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(glyph)
                    // W górę: stary glif odjeżdża do góry, nowy wjeżdża od dołu —
                    // serce „napełnia się” ruchem, a nie przenikaniem.
                    .contentTransition(.symbolEffect(.replace.upUp))
                    .transition(.opacity)
            }
        }
        .frame(width: 36, height: 36)
        .scSheetIconSurface(onImage: onImage)
        .contentShape(Circle())
        .animation(.smooth(duration: 0.2), value: isBusy)
    }
}

/// Powierzchnia krążka arkusza: tło (na zdjęciu kryjące, pod szkłem),
/// obwódka i cień. Jedna dla krzyżyka, jego sąsiadów i pierścienia kroków
/// trybu Gotuj (`CookStepRing`), który stoi naprzeciw krzyżyka na zdjęciu
/// i ma wyglądać jak jego para.
struct SCSheetIconSurface: ViewModifier {
    let onImage: Bool

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                if onImage {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.scCanvas(scheme).opacity(0.78)))
                }
                Circle().fill(Color.scChipBg(scheme))
            }
            .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
            .shadow(color: .black.opacity(onImage ? (scheme == .dark ? 0.35 : 0.16) : 0), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func scSheetIconSurface(onImage: Bool) -> some View {
        modifier(SCSheetIconSurface(onImage: onImage))
    }
}

#Preview("SCSheetCloseButton") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        HStack(spacing: 10) {
            SCSheetIconButton(systemName: "heart.fill", tint: SCPalette.terracotta, accessibilityLabel: "Ulubione") {}
            SCSheetCloseButton {}
            SCSheetCloseButton(onImage: true) {}
        }
    }
    .preferredColorScheme(.dark)
}
